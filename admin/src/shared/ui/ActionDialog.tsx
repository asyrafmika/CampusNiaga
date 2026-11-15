import { Button, Dialog, DialogActions, DialogContent, DialogContentText, DialogTitle, TextField } from '@mui/material';
import { useState } from 'react';

type ActionDialogProps = {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  /** Destructive actions get a red button. */
  danger?: boolean;
  /** Explains where the note goes. */
  noteHelp?: string;
  busy: boolean;
  onCancel: () => void;
  onConfirm: (note: string) => void;
};

/** Confirms a moderation action and collects an optional note for the audit log. */
export function ActionDialog({
  open,
  title,
  message,
  confirmLabel,
  danger = false,
  noteHelp = 'Saved in the audit log.',
  busy,
  onCancel,
  onConfirm,
}: ActionDialogProps) {
  const [note, setNote] = useState('');

  return (
    <Dialog
      open={open}
      onClose={onCancel}
      fullWidth
      maxWidth="xs"
      slotProps={{
        transition: {
          onExited: () => {
            setNote('');
          },
        },
      }}
    >
      <DialogTitle>{title}</DialogTitle>
      <DialogContent>
        <DialogContentText sx={{ mb: 2 }}>{message}</DialogContentText>
        <TextField
          label="Note (optional)"
          helperText={noteHelp}
          value={note}
          onChange={(e) => {
            setNote(e.target.value);
          }}
          fullWidth
          multiline
          minRows={2}
          slotProps={{ htmlInput: { maxLength: 500 } }}
        />
      </DialogContent>
      <DialogActions>
        <Button onClick={onCancel} disabled={busy}>
          Cancel
        </Button>
        <Button
          variant="contained"
          color={danger ? 'error' : 'primary'}
          disabled={busy}
          onClick={() => {
            onConfirm(note);
          }}
        >
          {confirmLabel}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
