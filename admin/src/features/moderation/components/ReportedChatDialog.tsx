import { Alert, Box, Button, Dialog, DialogActions, DialogContent, DialogTitle, Stack, Typography } from '@mui/material';

import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime } from '../../../shared/lib/format';
import { useReportedChat } from '../hooks/useModeration';

type ReportedChatDialogProps = {
  /** The report whose chat to show; null keeps the dialog closed. */
  reportId: string | null;
  onClose: () => void;
};

/** Read-only view of a reported deal chat (ADR 0004). Opening it is audited. */
export function ReportedChatDialog({ reportId, onClose }: ReportedChatDialogProps) {
  const chat = useReportedChat(reportId);
  const data = chat.data;

  return (
    <Dialog open={reportId !== null} onClose={onClose} fullWidth maxWidth="sm" aria-labelledby="reported-chat-title">
      <DialogTitle id="reported-chat-title">
        Reported chat
        {data !== undefined && (
          <Typography variant="body2" sx={{ color: 'text.secondary' }}>
            About “{data.listingTitle}” · buyer {data.buyer.name} ({data.buyer.email}) · seller {data.seller.name} (
            {data.seller.email})
          </Typography>
        )}
      </DialogTitle>
      <DialogContent dividers>
        <Alert severity="info" sx={{ mb: 2 }}>
          You can see this chat only because it was reported. Opening it is recorded in the audit log.
        </Alert>
        {chat.isLoading && <Typography sx={{ color: 'text.secondary' }}>Loading the chat…</Typography>}
        {chat.isError && <Alert severity="error">{messageOf(chat.error)}</Alert>}
        {data !== undefined && data.messages.length === 0 && (
          <Typography sx={{ color: 'text.secondary' }}>This chat has no messages.</Typography>
        )}
        {data !== undefined && (
          <Stack spacing={1}>
            {data.messages.map((m) => {
              const person = m.from === 'buyer' ? data.buyer : data.seller;
              return (
                <Box
                  key={m.id}
                  sx={{
                    alignSelf: m.from === 'buyer' ? 'flex-start' : 'flex-end',
                    maxWidth: '80%',
                    px: 1.5,
                    py: 1,
                    borderRadius: 2,
                    bgcolor: m.from === 'buyer' ? 'grey.100' : 'action.selected',
                  }}
                >
                  <Typography variant="caption" sx={{ fontWeight: 600, display: 'block' }}>
                    {person.name} ({m.from}) · {formatDateTime(m.createdAt)}
                  </Typography>
                  <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                    {m.body}
                  </Typography>
                </Box>
              );
            })}
            {data.closedAt !== null && (
              <Typography variant="body2" sx={{ color: 'text.secondary', textAlign: 'center', pt: 1 }}>
                A participant closed this chat on {formatDateTime(data.closedAt)}.
              </Typography>
            )}
          </Stack>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Close</Button>
      </DialogActions>
    </Dialog>
  );
}
