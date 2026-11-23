// Public surface of the auth feature.
export { isStaff, roleLabel, type StaffAccess } from './access';
export { RequireStaff } from './components/RequireStaff';
export { accessQueryKey, useAccess } from './hooks/useAccess';
export { LoginPage } from './pages/LoginPage';
export { signOut } from './services/authService';
