import { createClient } from 'npm:@supabase/supabase-js@2';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });
const secret = Deno.env.get('MOOD_SESSION_SECRET');
const encoder = new TextEncoder();
async function verify(token: string) {
  if (!secret || secret.length < 32) throw new Error('Server configuration error');
  const p = token.split('.'); if (p.length !== 3) throw new Error('Invalid session');
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  const sig = Uint8Array.from(atob(p[2].replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
  if (!await crypto.subtle.verify('HMAC', key, sig, encoder.encode(`${p[0]}.${p[1]}`))) throw new Error('Invalid session');
  const payload = JSON.parse(atob(p[1].replace(/-/g, '+').replace(/_/g, '/')));
  if (!payload.sub || payload.exp < Math.floor(Date.now() / 1000)) throw new Error('Session expired');
  return payload as { sub: string };
}
function json(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }); }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  try {
    const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
    const claims = await verify(token);
    const { data: actor, error: actorError } = await supabase.from('employees_auth').select('id, role, is_active').eq('id', claims.sub).maybeSingle();
    if (actorError || !actor || actor.is_active !== true || String(actor.role ?? '').toLowerCase().trim() !== 'head') return json({ error: 'AI access is restricted to active head accounts' }, 403);

    const body = await req.json();
    const question = String(body.question ?? '').trim();
    if (!question || question.length > 1200) return json({ error: 'Question is required and must be at most 1200 characters' }, 400);
    const q = question.toLowerCase();
    let tool = 'order_stats';
    let data: unknown;
    if (/(audit|change|changed|تغيير|تغييرات|اتغير|اتغيرت|مشكلة متكررة|recurring)/i.test(q)) {
      tool = 'audit_summary';
      const { data: result, error } = await supabase.rpc('mood_ai_audit_summary', { p_days: 30 });
      if (error) throw error; data = result;
    } else if (/(compare|comparison|versus|vs\b|مقارنة|قارن|مقارن)/i.test(q)) {
      tool = 'compare_periods';
      const now = new Date();
      const currentEnd = now.toISOString().slice(0, 10);
      const currentStartDate = new Date(now); currentStartDate.setDate(currentStartDate.getDate() - 29);
      const previousEndDate = new Date(currentStartDate); previousEndDate.setDate(previousEndDate.getDate() - 1);
      const previousStartDate = new Date(previousEndDate); previousStartDate.setDate(previousStartDate.getDate() - 29);
      const [current, previous] = await Promise.all([
        supabase.rpc('mood_ai_order_stats', { p_start_date: currentStartDate.toISOString().slice(0, 10), p_end_date: currentEnd }),
        supabase.rpc('mood_ai_order_stats', { p_start_date: previousStartDate.toISOString().slice(0, 10), p_end_date: previousEndDate.toISOString().slice(0, 10) }),
      ]);
      if (current.error) throw current.error; if (previous.error) throw previous.error;
      data = { current_30_days: current.data, previous_30_days: previous.data };
    } else if (/(workload|work load|performance|employee|employees|موظف|الموظفين|أداء|عبء|شغل مين|توزيع الشغل)/i.test(q)) {
      tool = 'employee_workload';
      const { data: result, error } = await supabase.rpc('mood_ai_employee_workload');
      if (error) throw error; data = result;
    } else if (/(search|find|lookup|order number|design order|contract|ابحث|دور على|هات الطلب|رقم الطلب|عقد|design_order)/i.test(q)) {
      tool = 'search_orders';
      let searchTerm = String(body.search_term ?? '').trim();
      if (!searchTerm) {
        const identifier = question.match(/[A-Z]{1,8}[-_/]?[A-Z0-9]{2,20}|\b\d{4,}\b/i);
        searchTerm = identifier?.[0] ?? question.replace(/(please|search|find|lookup|order|design|contract|ابحث|دور على|هات الطلب|رقم الطلب|من فضلك)/ig, ' ').trim();
      }
      searchTerm = searchTerm.slice(0, 120);
      const { data: result, error } = await supabase.rpc('mood_ai_search_orders', { p_search: searchTerm, p_limit: 20 });
      if (error) throw error; data = { search_term: searchTerm, results: result };
    } else {
      tool = 'order_stats';
      const { data: result, error } = await supabase.rpc('mood_ai_order_stats', { p_start_date: null, p_end_date: null });
      if (error) throw error; data = result;
    }

    const apiKey = Deno.env.get('GEMINI_API_KEY');
    if (!apiKey) return json({ error: 'Gemini is not configured on the server' }, 503);
    const prompt = `You are MOOD, a read-only internal operations analyst for Mobica. Answer in the same language as the user's question (Arabic or English). Only state facts supported by the supplied database result. If comparison data is provided, compare the current 30 days against the previous 30 days and name both periods explicitly. If data is insufficient, say so. Do not invent employee performance judgments; describe measured counts neutrally. Never claim you changed data. Tool used: ${tool}.\nUser question: ${question}\nDatabase result JSON:\n${JSON.stringify(data).slice(0, 18000)}`;
    const model = Deno.env.get('GEMINI_MODEL') || 'gemini-2.5-flash';
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }], generationConfig: { temperature: 0.2, maxOutputTokens: 900 } }),
    });
    if (!response.ok) { console.error('Gemini API status:', response.status, await response.text()); return json({ error: 'AI provider request failed' }, 502); }
    const result = await response.json();
    const answer = result?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? '').join('').trim();
    if (!answer) return json({ error: 'The AI returned an empty response' }, 502);
    return json({ answer, tool, data });
  } catch (e) {
    console.error('mood-ai error:', e);
    const message = e instanceof Error ? e.message : 'Request failed';
    const status = /session|token/i.test(message) ? 401 : 500;
    return json({ error: status === 500 ? 'Unable to process the question right now' : message }, status);
  }
});
