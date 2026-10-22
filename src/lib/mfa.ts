/** Two-step sign-in with an authenticator app (TOTP), through Supabase Auth. */
import { supabase } from './supabase';

export interface Enrolment { factorId: string; qr: string; secret: string }

/** Starts setting up an authenticator: removes unfinished attempts first, returns the QR code to scan. */
export async function startEnrolment(): Promise<Enrolment> {
  const list = await supabase.auth.mfa.listFactors();
  if (list.error) throw list.error;
  for (const f of list.data.all) {
    if (f.status !== 'verified') await supabase.auth.mfa.unenroll({ factorId: f.id });
  }
  const { data, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: `AACT HRMS ${new Date().toISOString().slice(0, 16)}` });
  if (error) throw error;
  return { factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret };
}

/** Checks a 6-digit code for a factor (finishes set-up, or passes the second step at sign-in). */
export async function verifyCode(factorId: string, code: string): Promise<void> {
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code: code.replace(/\s+/g, '') });
  if (error) throw error;
}

/** The verified authenticator of the signed-in user, if any. */
export async function verifiedFactor(): Promise<{ id: string; name: string | null; created_at: string } | null> {
  const { data, error } = await supabase.auth.mfa.listFactors();
  if (error) throw error;
  const f = data.totp.find((x) => x.status === 'verified');
  return f ? { id: f.id, name: f.friendly_name ?? null, created_at: f.created_at } : null;
}

export async function removeFactor(factorId: string): Promise<void> {
  const { error } = await supabase.auth.mfa.unenroll({ factorId });
  if (error) throw error;
}

/** A 6-digit code as typed (spaces allowed). */
export function codeOk(code: string): boolean {
  return /^\d{6}$/.test(code.replace(/\s+/g, ''));
}
