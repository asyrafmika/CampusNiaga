import LogoutOutlinedIcon from '@mui/icons-material/LogoutOutlined';
import StorefrontRoundedIcon from '@mui/icons-material/StorefrontRounded';
import {
  Avatar,
  Box,
  Chip,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Paper,
  Stack,
  Typography,
} from '@mui/material';
import { NavLink, Outlet, useLocation } from 'react-router';

import { roleLabel, signOut, useAccess, type StaffAccess } from '../../features/auth';
import { palette } from '../theme';
import { visibleNavItems } from './navigation';

const SIDEBAR_WIDTH = 260;

function Sidebar({ access }: { access: StaffAccess }) {
  const { pathname } = useLocation();
  return (
    <Box
      component="nav"
      aria-label="Main"
      sx={{
        width: SIDEBAR_WIDTH,
        flexShrink: 0,
        bgcolor: 'background.paper',
        borderRight: 1,
        borderColor: 'divider',
        display: 'flex',
        flexDirection: 'column',
        p: 3,
        position: 'sticky',
        top: 0,
        height: '100vh',
      }}
    >
      <Stack direction="row" spacing={1.5} sx={{ alignItems: 'center', mb: 4 }}>
        <Box
          sx={{
            width: 40,
            height: 40,
            borderRadius: 2,
            bgcolor: palette.primary,
            color: '#fff',
            display: 'grid',
            placeItems: 'center',
          }}
        >
          <StorefrontRoundedIcon fontSize="small" />
        </Box>
        <Typography variant="h2" component="p">
          CampusNiaga
        </Typography>
      </Stack>

      <List disablePadding sx={{ flexGrow: 1 }}>
        {visibleNavItems(access).map((item) => {
          const active = item.path === '/' ? pathname === '/' : pathname.startsWith(item.path);
          const disabled = item.comingIn !== undefined;
          return (
            <ListItemButton
              key={item.path}
              component={NavLink}
              to={item.path}
              disabled={disabled}
              selected={active}
              sx={{
                borderRadius: 2,
                mb: 0.5,
                color: 'text.secondary',
                '& .MuiListItemIcon-root': { color: 'inherit', minWidth: 40 },
                '&.Mui-selected, &.Mui-selected:hover': {
                  bgcolor: palette.primary,
                  color: '#fff',
                  boxShadow: '0 20px 50px rgba(55, 69, 87, 0.1)',
                },
              }}
            >
              <ListItemIcon>{item.icon}</ListItemIcon>
              <ListItemText primary={item.label} />
              {disabled && <Chip label={item.comingIn} size="small" />}
            </ListItemButton>
          );
        })}
      </List>

      <Paper
        sx={{
          p: 2.5,
          mt: 2,
          bgcolor: palette.primary,
          color: '#fff',
          boxShadow: 'none',
        }}
      >
        <Typography sx={{ fontWeight: 600, mb: 0.5 }}>Prototype</Typography>
        <Typography variant="body2" sx={{ opacity: 0.9 }}>
          Simulated reviewer workflow for a USM Final Year Project. Not an official USM or HDC decision.
        </Typography>
      </Paper>

      <ListItemButton
        onClick={() => void signOut()}
        sx={{ borderRadius: 2, mt: 2, color: 'text.secondary' }}
      >
        <ListItemIcon sx={{ color: 'inherit', minWidth: 40 }}>
          <LogoutOutlinedIcon />
        </ListItemIcon>
        <ListItemText primary="Sign out" />
      </ListItemButton>
    </Box>
  );
}

function TopBar({ access }: { access: StaffAccess }) {
  return (
    <Stack
      direction="row"
      sx={{
        justifyContent: 'flex-end',
        alignItems: 'center',
        px: 4,
        py: 2,
        bgcolor: 'background.paper',
        borderBottom: 1,
        borderColor: 'divider',
      }}
    >
      <Stack direction="row" spacing={1.5} sx={{ alignItems: 'center' }}>
        <Avatar sx={{ bgcolor: palette.tiles.purple.icon, width: 40, height: 40 }}>
          {access.email.charAt(0).toUpperCase()}
        </Avatar>
        <Box>
          <Typography sx={{ fontWeight: 500, lineHeight: 1.2 }}>{access.email}</Typography>
          <Typography variant="body2" sx={{ color: 'text.secondary' }}>
            {roleLabel(access)}
          </Typography>
        </Box>
      </Stack>
    </Stack>
  );
}

/** Sidebar, top bar and the current page. Only rendered inside RequireStaff. */
export function AppShell() {
  const state = useAccess();
  if (state.status !== 'ready') return null;
  return (
    <Box sx={{ display: 'flex', minHeight: '100vh', bgcolor: 'background.default' }}>
      <Sidebar access={state.access} />
      <Box sx={{ flexGrow: 1, minWidth: 0 }}>
        <TopBar access={state.access} />
        <Box component="main" sx={{ p: 4 }}>
          <Outlet />
        </Box>
      </Box>
    </Box>
  );
}
