import { onCall } from 'firebase-functions/v2/https';
import { syncStudent } from '../../services/studentService';
import { requireAuth, type CallableInput } from '../../shared/guards';

export const syncStudentStatusHandler = (req: CallableInput) => syncStudent(requireAuth(req));

export const syncStudentStatus = onCall(syncStudentStatusHandler);
