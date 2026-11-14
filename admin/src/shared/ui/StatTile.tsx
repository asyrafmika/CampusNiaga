import { Box, Paper, Typography } from '@mui/material';
import type { ReactNode } from 'react';

import { palette, type TileColour } from '../../app/theme';

type StatTileProps = {
  colour: TileColour;
  icon: ReactNode;
  value: string;
  label: string;
  note?: string;
};

/** Pastel summary tile, as in the "Today's Sales" row of the reference. */
export function StatTile({ colour, icon, value, label, note }: StatTileProps) {
  const tone = palette.tiles[colour];
  return (
    <Paper sx={{ p: 2.5, bgcolor: tone.background, boxShadow: 'none', height: '100%' }}>
      <Box
        sx={{
          width: 40,
          height: 40,
          borderRadius: '50%',
          bgcolor: tone.icon,
          color: '#fff',
          display: 'grid',
          placeItems: 'center',
          mb: 2,
        }}
      >
        {icon}
      </Box>
      <Typography variant="h2" component="p">
        {value}
      </Typography>
      <Typography sx={{ color: 'text.primary', fontWeight: 500, mt: 0.5 }}>{label}</Typography>
      {note !== undefined && (
        <Typography variant="body2" sx={{ color: tone.icon, mt: 0.5 }}>
          {note}
        </Typography>
      )}
    </Paper>
  );
}
