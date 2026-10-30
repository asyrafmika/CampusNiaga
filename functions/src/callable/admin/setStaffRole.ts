import { onCall } from 'firebase-functions/v2/https';
import * as staffRoles from '../../services/staffRoleService';
import { requireAdmin, type CallableInput } from '../../shared/guards';
import { parse } from '../../shared/validation';

export const setStaffRoleHandler = async (req: CallableInput) => {
  const actor = await requireAdmin(req);
  const input = parse(staffRoles.SetStaffRoleInput, req.data);
  return staffRoles.setStaffRole(actor, input);
};

export const setStaffRole = onCall(setStaffRoleHandler);
