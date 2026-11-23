import AssignmentOutlinedIcon from '@mui/icons-material/AssignmentOutlined';
import DashboardOutlinedIcon from '@mui/icons-material/DashboardOutlined';
import FlagOutlinedIcon from '@mui/icons-material/FlagOutlined';
import HistoryOutlinedIcon from '@mui/icons-material/HistoryOutlined';
import InsightsOutlinedIcon from '@mui/icons-material/InsightsOutlined';
import ManageAccountsOutlinedIcon from '@mui/icons-material/ManageAccountsOutlined';
import type { ReactNode } from 'react';

export type NavItem = {
  label: string;
  path: string;
  icon: ReactNode;
  /** Shown but disabled until the phase that builds it. */
  comingIn?: string;
};

/** The menu: every page is for HDC administrators, the one staff role (ADR 0009). */
export const NAV_ITEMS: readonly NavItem[] = [
  { label: 'Overview', path: '/', icon: <DashboardOutlinedIcon /> },
  { label: 'Applications', path: '/applications', icon: <AssignmentOutlinedIcon /> },
  { label: 'Business Performance', path: '/performance', icon: <InsightsOutlinedIcon /> },
  { label: 'Reports & Moderation', path: '/moderation', icon: <FlagOutlinedIcon /> },
  { label: 'Users & Roles', path: '/users', icon: <ManageAccountsOutlinedIcon /> },
  { label: 'Audit Log', path: '/audit', icon: <HistoryOutlinedIcon /> },
];
