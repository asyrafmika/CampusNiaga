import SearchIcon from '@mui/icons-material/Search';
import {
  Alert,
  Box,
  Button,
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

import { useAccess } from '../../auth';
import { useSetAccountStatus } from '../../moderation';
import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime, PAGE_SIZE } from '../../../shared/lib/format';
import { ActionDialog } from '../../../shared/ui/ActionDialog';
import { useSetAdminRole, useUsers } from '../hooks/useUsers';
import type { UserRow } from '../services/usersService';

export function UsersPage() {
  const access = useAccess();
  const myId = access.status === 'ready' ? access.access.userId : null;
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState('');
  const users = useUsers(page, search);
  const setRole = useSetAdminRole();
  const setStatus = useSetAccountStatus();
  const [statusTarget, setStatusTarget] = useState<UserRow | null>(null);
  const [notice, setNotice] = useState<{ severity: 'success' | 'error'; text: string } | null>(null);

  const toggle = (user: UserRow, enabled: boolean) => {
    setRole.mutate(
      { userId: user.id, enabled },
      {
        onSuccess: () => {
          setNotice({
            severity: 'success',
            text: `${user.email} ${enabled ? 'is now' : 'is no longer'} an HDC administrator.`,
          });
        },
        onError: (error) => {
          setNotice({ severity: 'error', text: messageOf(error) });
        },
      },
    );
  };

  const changeStatus = (note: string) => {
    if (statusTarget === null) return;
    const suspend = statusTarget.accountStatus === 'active';
    const email = statusTarget.email;
    setStatus.mutate(
      { userId: statusTarget.id, status: suspend ? 'suspended' : 'active', note },
      {
        onSuccess: () => {
          setStatusTarget(null);
          setNotice({ severity: 'success', text: `${email} is ${suspend ? 'suspended' : 'active again'}.` });
        },
        onError: (error) => {
          setStatusTarget(null);
          setNotice({ severity: 'error', text: messageOf(error) });
        },
      },
    );
  };

  return (
    <Box>
      <Typography variant="h1">Users &amp; Roles</Typography>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        Grant or remove HDC administrator access, and suspend accounts. Every change is recorded in the audit log.
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
                <TableCell align="center">HDC Administrator</TableCell>
                <TableCell align="right">Account</TableCell>
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
                        checked={user.isAdmin}
                        disabled={setRole.isPending || (isMe && user.isAdmin)}
                        onChange={(_e, checked) => {
                          toggle(user, checked);
                        }}
                        slotProps={{ input: { 'aria-label': `Administrator role for ${user.email}` } }}
                      />
                    </TableCell>
                    <TableCell align="right">
                      {!isMe && (
                        <Button
                          size="small"
                          color={user.accountStatus === 'active' ? 'error' : 'primary'}
                          disabled={setStatus.isPending}
                          onClick={() => {
                            setStatusTarget(user);
                          }}
                          aria-label={`${user.accountStatus === 'active' ? 'Suspend' : 'Reactivate'} ${user.email}`}
                        >
                          {user.accountStatus === 'active' ? 'Suspend' : 'Reactivate'}
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
              {users.data?.rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={7} align="center" sx={{ color: 'text.secondary', py: 4 }}>
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

      {statusTarget !== null && (
        <ActionDialog
          open
          title={statusTarget.accountStatus === 'active' ? 'Suspend account?' : 'Reactivate account?'}
          message={
            statusTarget.accountStatus === 'active'
              ? `${statusTarget.email} can no longer buy or sell, and their listings leave the marketplace.`
              : `${statusTarget.email} can trade again.`
          }
          confirmLabel={statusTarget.accountStatus === 'active' ? 'Suspend' : 'Reactivate'}
          danger={statusTarget.accountStatus === 'active'}
          busy={setStatus.isPending}
          onCancel={() => {
            setStatusTarget(null);
          }}
          onConfirm={changeStatus}
        />
      )}

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
