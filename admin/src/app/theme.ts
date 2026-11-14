import { createTheme } from '@mui/material/styles';

/** Colours from the Dabang dashboard reference. */
export const palette = {
  primary: '#5D5FEF',
  page: '#FAFBFC',
  text: '#151D48',
  textSecondary: '#737791',
  border: '#EDF2F6',
  tiles: {
    pink: { background: '#FFE2E5', icon: '#FA5A7D' },
    orange: { background: '#FFF4DE', icon: '#FF947A' },
    green: { background: '#DCFCE7', icon: '#3CD856' },
    purple: { background: '#F3E8FF', icon: '#BF83FF' },
  },
} as const;

export type TileColour = keyof typeof palette.tiles;

export const theme = createTheme({
  palette: {
    primary: { main: palette.primary },
    background: { default: palette.page, paper: '#FFFFFF' },
    text: { primary: palette.text, secondary: palette.textSecondary },
    divider: palette.border,
  },
  typography: {
    fontFamily: '"Poppins", "Segoe UI", Roboto, sans-serif',
    h1: { fontSize: '2rem', fontWeight: 600 },
    h2: { fontSize: '1.25rem', fontWeight: 600 },
    h3: { fontSize: '1.05rem', fontWeight: 600 },
    button: { textTransform: 'none', fontWeight: 500 },
  },
  shape: { borderRadius: 12 },
  components: {
    MuiPaper: {
      defaultProps: { elevation: 0 },
      styleOverrides: {
        root: { boxShadow: '0 4px 20px rgba(238, 238, 238, 0.5)' },
      },
    },
    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: { root: { borderRadius: 12, paddingBlock: 10 } },
    },
    MuiTableCell: {
      styleOverrides: {
        head: { color: palette.textSecondary, fontWeight: 500 },
      },
    },
  },
});
