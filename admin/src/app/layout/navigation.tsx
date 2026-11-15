import AssignmentOutlinedIcon from '@mui/icons-material/AssignmentOutlined';
import DashboardOutlinedIcon from '@mui/icons-material/DashboardOutlined';
import FlagOutlinedIcon from '@mui/icons-material/FlagOutlined';
import HistoryOutlinedIcon from '@mui/icons-material/HistoryOutlined';
import ManageAccountsOutlinedIcon from '@mui/icons-material/ManageAccountsOutlined';
import type { ReactNode } from 'react';

import { hasRole, type StaffAccess, type StaffRole } from '../../features/auth';

export type NavItem = {
  label: string;
  path: string;
  icon: ReactNode;
  role: StaffRole;
  /** Shown but disabled until the phase that builds it. */
  comingIn?: string;
};

export const NAV_ITEMS: readonly NavItem[] = [
  { label: 'Overview', path: '/', icon: <DashboardOutlinedIcon />, role: 'reviewer' },
  {
    label: 'Applications',
    path: '/applications',
    icon: <AssignmentOutlinedIcon />,
    role: 'reviewer',
    comingIn: 'Phase 3',
  },
  {
    label: 'Reports & Moderation',
    path: '/moderation',
    icon: <FlagOutlinedIcon />,
    role: 'admin',
  },
  { label: 'Users & Roles', path: '/users', icon: <ManageAccountsOutlinedIcon />, role: 'admin' },
  { label: 'Audit Log', path: '/audit', icon: <HistoryOutlinedIcon />, role: 'admin' },
];

/** The menu entries this user may see. */
export function visibleNavItems(access: StaffAccess): NavItem[] {
  return NAV_ITEMS.filter((item) => hasRole(access, item.role));
}
