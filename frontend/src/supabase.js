import { createClient } from '@supabase/supabase-js'

// Las claves vienen del archivo .env.local (NO se sube a Git)
const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_KEY

// db.schema = 'erp' → todas las consultas van a nuestro schema, no a public
export const supabase = createClient(url, key, { db: { schema: 'erp' } })