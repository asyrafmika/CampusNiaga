import { createClient } from '@supabase/supabase-js';

import type { Database } from '../types/database';

/**
 * The CampusNiaga Supabase project. The publishable key is designed to be
 * public: Row Level Security in the database decides what each user may do.
 * Never put the secret (service_role) key here.
 */
export const SUPABASE_URL = 'https://abctyhurvvprthgwrxyi.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_eG3N5cMp9hbVj_fcfukRpA_Ge-NV8AE';

/** Only `services/` files import this. */
export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
