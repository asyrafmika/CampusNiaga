import { onCall } from 'firebase-functions/v2/https';
import * as staffRoles from '../../services/staffRoleService';
import { requireAdmin, type CallableInput } from '../../shared/guards';
import { parse } from '../../shared/validation';

export const setStaffRoleHandler = (req: CallableInput) => {
  const actor = requireAdmin(req);
  const input = parse(staffRoles.SetStaffRoleInput, req.data);
  return staffRoles.setStaffRole(actor, input);
};

export const setStaffRole = onCall(setStaffRoleHandler);
