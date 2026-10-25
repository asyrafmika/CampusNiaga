import { FieldValue, type Transaction, type WriteBatch } from 'firebase-admin/firestore';
import { COLLECTIONS } from '../domain/types';
import { db } from './firebase';

export interface AuditEntry {
  actorUid: string;
  /** Dotted verb, e.g. `role.granted`, `application.approved`. */
  action: string;
  targetType: string;
  targetId: string;
  /** Minimal context only; never personal or sensitive data. */
  metadata?: Record<string, string | number | boolean>;
}

/**
 * Appends an audit log entry as part of an existing transaction or batch,
 * so the entry commits atomically with the change it records.
 */
export function writeAudit(writer: Transaction | WriteBatch, entry: AuditEntry): void {
  const ref = db.collection(COLLECTIONS.auditLogs).doc();
  writer.create(ref, { ...entry, at: FieldValue.serverTimestamp() });
}
