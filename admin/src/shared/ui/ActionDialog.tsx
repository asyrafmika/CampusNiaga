import { Button, Dialog, DialogActions, DialogContent, DialogContentText, DialogTitle, TextField } from '@mui/material';
import { useState, type ReactNode } from 'react';

type ActionDialogProps = {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  /** Destructive actions get a red button. */
  danger?: boolean;
  /** Explains where the note goes. */
  noteHelp?: string;
  /** The action can't be confirmed without a note (e.g. rejecting). */
  noteRequired?: boolean;
  noteMaxLength?: number;
  /** Shown above the note, e.g. a disclaimer. */
  notice?: ReactNode;
  busy: boolean;
  onCancel: () => void;
  onConfirm: (note: string) => void;
};

/** Confirms a staff action and collects a note (optional unless [noteRequired]) for the audit log. */
export function ActionDialog({
  open,
  title,
  message,
  confirmLabel,
  danger = false,
  noteHelp = 'Saved in the audit log.',
  noteRequired = false,
  noteMaxLength = 500,
  notice,
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
        {notice}
        <TextField
          label={noteRequired ? 'Note (required)' : 'Note (optional)'}
          required={noteRequired}
          helperText={noteHelp}
          value={note}
          onChange={(e) => {
            setNote(e.target.value);
          }}
          fullWidth
          multiline
          minRows={2}
          slotProps={{ htmlInput: { maxLength: noteMaxLength } }}
        />
      </DialogContent>
      <DialogActions>
        <Button onClick={onCancel} disabled={busy}>
          Cancel
        </Button>
        <Button
          variant="contained"
          color={danger ? 'error' : 'primary'}
          disabled={busy || (noteRequired && note.trim().length === 0)}
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
