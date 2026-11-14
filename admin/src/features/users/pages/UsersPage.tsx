import SearchIcon from '@mui/icons-material/Search';
import {
  Alert,
  Box,
  Chip,
  InputAdornment,
  Paper,
  Snackbar,
  Switch,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TablePagination,
  TableRow,
  TextField,
  Typography,
} from '@mui/material';
import { useState } from 'react';

import { useAccess, type StaffRole } from '../../auth';
import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime, PAGE_SIZE } from '../../../shared/lib/format';
import { useSetStaffRole, useUsers } from '../hooks/useUsers';
import type { UserRow } from '../services/usersService';

export function UsersPage() {
  const access = useAccess();
  const myId = access.status === 'ready' ? access.access.userId : null;
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState('');
  const users = useUsers(page, search);
  const setRole = useSetStaffRole();
  const [notice, setNotice] = useState<{ severity: 'success' | 'error'; text: string } | null>(null);

  const toggle = (user: UserRow, role: StaffRole, enabled: boolean) => {
    setRole.mutate(
      { userId: user.id, role, enabled },
      {
        onSuccess: () => {
          setNotice({
            severity: 'success',
            text: `${user.email} ${enabled ? 'is now' : 'is no longer'} ${role === 'admin' ? 'an admin' : 'a reviewer'}.`,
          });
        },
        onError: (error) => {
          setNotice({ severity: 'error', text: messageOf(error) });
        },
      },
    );
  };

  return (
    <Box>
      <Typography variant="h1">Users &amp; Roles</Typography>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        Grant or remove reviewer and admin access. Every change is recorded in the audit log.
      </Typography>

      <Paper sx={{ p: 3 }}>
        <TextField
          placeholder="Search by email"
          size="small"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(0);
          }}
          sx={{ mb: 2, width: { xs: '100%', sm: 320 } }}
          slotProps={{
            input: {
              startAdornment: (
                <InputAdornment position="start">
                  <SearchIcon fontSize="small" />
                </InputAdornment>
              ),
            },
          }}
        />

        {users.isError && <Alert severity="error">{messageOf(users.error)}</Alert>}

        <TableContainer>
          <Table aria-label="Users">
            <TableHead>
              <TableRow>
                <TableCell>Name</TableCell>
                <TableCell>Email</TableCell>
                <TableCell>Status</TableCell>
                <TableCell>Joined</TableCell>
                <TableCell align="center">Reviewer</TableCell>
                <TableCell align="center">Admin</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {users.data?.rows.map((user) => {
                const isMe = user.id === myId;
                return (
                  <TableRow key={user.id} hover>
                    <TableCell>
                      {user.name}
                      {isMe && <Chip label="You" size="small" sx={{ ml: 1 }} />}
                    </TableCell>
                    <TableCell>{user.email}</TableCell>
                    <TableCell>
                      <Chip
                        label={user.accountStatus === 'active' ? 'Active' : 'Suspended'}
                        color={user.accountStatus === 'active' ? 'success' : 'warning'}
                        size="small"
                        variant="outlined"
                      />
                    </TableCell>
                    <TableCell>{formatDateTime(user.createdAt)}</TableCell>
                    <TableCell align="center">
                      <Switch
                        checked={user.isReviewer}
                        disabled={setRole.isPending}
                        onChange={(_e, checked) => {
                          toggle(user, 'reviewer', checked);
                        }}
                        slotProps={{ input: { 'aria-label': `Reviewer role for ${user.email}` } }}
                      />
                    </TableCell>
                    <TableCell align="center">
                      <Switch
                        checked={user.isAdmin}
                        disabled={setRole.isPending || (isMe && user.isAdmin)}
                        onChange={(_e, checked) => {
                          toggle(user, 'admin', checked);
                        }}
                        slotProps={{ input: { 'aria-label': `Admin role for ${user.email}` } }}
                      />
                    </TableCell>
                  </TableRow>
                );
              })}
              {users.data?.rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                    No accounts match.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </TableContainer>

        <TablePagination
          component="div"
          count={users.data?.total ?? 0}
          page={page}
          rowsPerPage={PAGE_SIZE}
          rowsPerPageOptions={[PAGE_SIZE]}
          onPageChange={(_e, next) => {
            setPage(next);
          }}
        />
      </Paper>

      <Snackbar
        open={notice !== null}
        autoHideDuration={4000}
        onClose={() => {
          setNotice(null);
        }}
      >
        {notice === null ? undefined : (
          <Alert severity={notice.severity} variant="filled">
            {notice.text}
          </Alert>
        )}
      </Snackbar>
    </Box>
  );
}
