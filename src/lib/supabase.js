import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey =
  import.meta.env.VITE_SUPABASE_ANON_KEY || import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

const isAllowedSupabaseUrl = (value) => {
  if (!value) return false

  try {
    const parsed = new URL(value)
    const isHttps = parsed.protocol === 'https:'
    const isLocalhost = parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1'
    return isHttps || isLocalhost
  } catch {
    return false
  }
}

if (supabaseUrl && !isAllowedSupabaseUrl(supabaseUrl)) {
  console.warn('Supabase disabled: VITE_SUPABASE_URL must be https or localhost.')
}

export const supabase =
  isAllowedSupabaseUrl(supabaseUrl) && supabaseKey
    ? createClient(supabaseUrl, supabaseKey)
    : null
