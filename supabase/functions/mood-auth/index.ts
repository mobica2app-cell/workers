import { createClient } from 'npm:@supabase/supabase-js@2';
import bcrypt from 'npm:bcryptjs@2.4.3';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);
const secret = Deno.env.get('MOOD_SESSION_SECRET');
if (!secret || secret.length < 32) throw new Error('MOOD_SESSION_SECRET must be at least 32 characters');

const encoder = new TextEncoder();
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const encodeJson = (v: unknown) => b64url(encoder.encode(JSON.stringify(v)));
async function sign(payload: Record<string, unknown>) {
  const header = encodeJson({ alg: 'HS256', typ: 'JWT' });
  const body = encodeJson(payload);
  const data = `${header}.${body}`;
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret!), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(data)));
  return `${data}.${b64url(signature)}`;
}
async function verify(token: string) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Invalid session');
  const data = `${parts[0]}.${parts[1]}`;
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret!), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  const sigText = parts[2].replace(/-/g, '+').replace(/_/g, '/');
  const sig = Uint8Array.from(atob(sigText + '='.repeat((4 - sigText.length % 4) % 4)), c => c.charCodeAt(0));
  if (!await crypto.subtle.verify('HMAC', key, sig, encoder.encode(data))) throw new Error('Invalid session');
  const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
  if (!payload.sub || payload.exp < Math.floor(Date.now() / 1000)) throw new Error('Session expired');
  return payload as { sub: string; exp: number };
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}
const publicEmployee = (e: Record<string, unknown>) => ({
  id: e.id, username: e.username, full_name: e.full_name, department: e.department,
  role: e.role, phone_number: e.phone_number, is_active: e.is_active,
  last_login: e.last_login, created_at: e.created_at,
});
const managerRoles = new Set(['head', 'software head', 'admin']);
const isBcryptHash = (value: string) => /^\$2[aby]\$\d\d\$/.test(value);
function passwordMatches(input: string, stored: string): boolean {
  if (isBcryptHash(stored)) {
    try { return bcrypt.compareSync(input, stored); } catch { return false; }
  }
  // Legacy compatibility: successful legacy plaintext login is immediately upgraded below.
  return input === stored;
}
function hashPassword(password: string): string { return bcrypt.hashSync(password, 12); }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  try {
    const body = await req.json();
    const action = String(body.action ?? '');

    if (action === 'login') {
      const username = String(body.username ?? '').trim();
      const password = String(body.password ?? '');
      if (!username || !password || username.length > 120 || password.length > 1024) return json({ error: 'Invalid username or password' }, 400);
      const { data: employee, error } = await supabase.from('employees_auth')
        .select('id, username, password, full_name, department, role, phone_number, is_active, last_login, created_at')
        .ilike('username', username).maybeSingle();
      if (error) {
        console.error('Login lookup failed:', error.message);
        return json({ error: 'Could not verify account' }, 500);
      }
      if (!employee || employee.is_active !== true || typeof employee.password !== 'string' || !passwordMatches(password, employee.password)) {
        return json({ error: 'Invalid username or password' }, 401);
      }
      // Upgrade legacy plaintext passwords to bcrypt in the existing `password` column.
      if (!isBcryptHash(employee.password)) {
        const { error: upgradeError } = await supabase.from('employees_auth')
          .update({ password: hashPassword(password), updated_at: new Date().toISOString() }).eq('id', employee.id);
        if (upgradeError) {
          console.error('Password hash upgrade failed:', upgradeError.message);
          return json({ error: 'Could not secure account credentials. Please try again.' }, 500);
        }
      }
      const lastLogin = new Date().toISOString();
      const { error: loginUpdateError } = await supabase.from('employees_auth').update({ last_login: lastLogin }).eq('id', employee.id);
      if (loginUpdateError) console.error('Could not update last_login:', loginUpdateError.message);
      const now = Math.floor(Date.now() / 1000);
      const token = await sign({ sub: employee.id, iat: now, exp: now + 8 * 60 * 60, iss: 'mood-manual-auth' });
      return json({ token, employee: publicEmployee({ ...employee, last_login: lastLogin }), expires_at: new Date((now + 8 * 60 * 60) * 1000).toISOString() });
    }

    const authHeader = req.headers.get('authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    const claims = await verify(token);
    const { data: actor, error: actorError } = await supabase.from('employees_auth')
      .select('id, role, is_active').eq('id', claims.sub).maybeSingle();
    if (actorError || !actor || actor.is_active !== true) return json({ error: 'Account inactive or unavailable' }, 401);
    const role = String(actor.role ?? '').toLowerCase().trim();
    const isManager = managerRoles.has(role);

    if (action === 'change_password') {
      const id = String(body.id ?? '');
      const password = String(body.password ?? '');
      if (id !== claims.sub) return json({ error: 'Not authorized to change another employee password' }, 403);
      if (password.length < 8 || password.length > 1024) return json({ error: 'Password must be at least 8 characters' }, 400);
      const { error } = await supabase.from('employees_auth')
        .update({ password: hashPassword(password), updated_at: new Date().toISOString() }).eq('id', claims.sub);
      if (error) throw error;
      return json({ success: true });
    }

    if (action === 'list_employees') {
      const { data, error } = await supabase.from('employees_auth')
        .select('id, username, full_name, department, role, phone_number, is_active, last_login, created_at')
        .eq('is_active', true).order('full_name');
      if (error) throw error;
      return json({ employees: data ?? [] });
    }
    if (action === 'get_employee') {
      const { data, error } = await supabase.from('employees_auth')
        .select('id, username, full_name, department, role, phone_number, is_active, last_login, created_at')
        .eq('id', String(body.id ?? '')).maybeSingle();
      if (error) throw error;
      return data ? json({ employee: data }) : json({ error: 'Employee not found' }, 404);
    }
    if (action === 'create_employee') {
      if (!isManager) return json({ error: 'Not authorized' }, 403);
      const username = String(body.username ?? '').trim();
      const password = String(body.password ?? '');
      const fullName = String(body.full_name ?? '').trim();
      if (!username || !fullName || password.length < 8 || password.length > 1024) return json({ error: 'Username, full name and password (at least 8 characters) are required' }, 400);
      const [usernameMatch, nameMatch] = await Promise.all([
        supabase.from('employees_auth').select('id').ilike('username', username).limit(1),
        supabase.from('employees_auth').select('id').ilike('full_name', fullName).limit(1),
      ]);
      if (usernameMatch.error) throw usernameMatch.error;
      if (nameMatch.error) throw nameMatch.error;
      if (usernameMatch.data?.length || nameMatch.data?.length) return json({ error: 'Username or full name already exists' }, 409);
      const { data, error } = await supabase.from('employees_auth').insert({
        username, password: hashPassword(password), full_name: fullName,
        department: body.department || null, role: body.role || 'employee',
        phone_number: body.phone_number || null, is_active: true,
      }).select('id, username, full_name, department, role, phone_number, is_active, last_login, created_at').single();
      if (error) throw error;
      return json({ employee: data });
    }
    if (action === 'update_employee') {
      if (!isManager) return json({ error: 'Not authorized' }, 403);
      const id = String(body.id ?? '');
      if (!id) return json({ error: 'Employee id is required' }, 400);
      const updates: Record<string, unknown> = { updated_at: new Date().toISOString() };
      for (const key of ['username', 'full_name', 'department', 'role', 'phone_number', 'is_active']) {
        if (Object.hasOwn(body, key)) updates[key] = body[key];
      }
      if (typeof updates.username === 'string' || typeof updates.full_name === 'string') {
        const username = String(updates.username ?? '');
        const fullName = String(updates.full_name ?? '');
        const checks = await Promise.all([
          ...(username ? [supabase.from('employees_auth').select('id').ilike('username', username).neq('id', id).limit(1)] : []),
          ...(fullName ? [supabase.from('employees_auth').select('id').ilike('full_name', fullName).neq('id', id).limit(1)] : []),
        ]);
        for (const check of checks) {
          if (check.error) throw check.error;
          if (check.data?.length) return json({ error: 'Username or full name already exists' }, 409);
        }
      }
      if (body.password !== undefined && body.password !== null && String(body.password).length > 0) {
        const newPassword = String(body.password);
        if (newPassword.length < 8 || newPassword.length > 1024) return json({ error: 'Password must be at least 8 characters' }, 400);
        updates.password = hashPassword(newPassword);
      }
      const { data, error } = await supabase.from('employees_auth').update(updates).eq('id', id)
        .select('id, username, full_name, department, role, phone_number, is_active, last_login, created_at').maybeSingle();
      if (error) throw error;
      return data ? json({ employee: data }) : json({ error: 'Employee not found' }, 404);
    }
    return json({ error: 'Unknown action' }, 400);
  } catch (e) {
    console.error('mood-auth error:', e instanceof Error ? e.message : 'Unknown error');
    const message = e instanceof Error ? e.message : 'Request failed';
    const status = /session|token/i.test(message) ? 401 : 500;
    return json({ error: status === 500 ? 'Server error' : message }, status);
  }
});
