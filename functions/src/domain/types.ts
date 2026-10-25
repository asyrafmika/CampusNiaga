// Mirror of docs/data-dictionary.md for Cloud Functions.
// Keep in sync with admin/src/shared/types/domain.ts and mobile/lib/core/domain/.

export const COLLECTIONS = {
  users: 'users',
  listings: 'listings',
  reservations: 'reservations',
  businessApplications: 'businessApplications',
  businesses: 'businesses',
  campaigns: 'campaigns',
  orders: 'orders',
  productRequests: 'productRequests',
  requestInterests: 'requestInterests',
  opportunities: 'opportunities',
  reports: 'reports',
  auditLogs: 'auditLogs',
  notifications: 'notifications',
  config: 'config',
} as const;

export const ACCOUNT_STATUSES = ['active', 'suspended'] as const;
export type AccountStatus = (typeof ACCOUNT_STATUSES)[number];

export const LISTING_MODES = ['personal', 'business'] as const;
export type ListingMode = (typeof LISTING_MODES)[number];

export const LISTING_CONDITIONS = ['new', 'like_new', 'good', 'fair'] as const;
export type ListingCondition = (typeof LISTING_CONDITIONS)[number];

export const LISTING_STATUSES = ['draft', 'available', 'reserved', 'sold', 'closed'] as const;
export type ListingStatus = (typeof LISTING_STATUSES)[number];

export const RESERVATION_STATUSES = [
  'requested',
  'accepted',
  'declined',
  'cancelled',
  'collected',
  'expired',
] as const;
export type ReservationStatus = (typeof RESERVATION_STATUSES)[number];

export const APPLICATION_STATUSES = [
  'draft',
  'submitted',
  'under_review',
  'info_requested',
  'approved',
  'rejected',
] as const;
export type ApplicationStatus = (typeof APPLICATION_STATUSES)[number];

export const BUSINESS_STATUSES = ['approved', 'suspended'] as const;
export type BusinessStatus = (typeof BUSINESS_STATUSES)[number];

export const CAMPAIGN_STATUSES = ['draft', 'open', 'closed'] as const;
export type CampaignStatus = (typeof CAMPAIGN_STATUSES)[number];

export const ORDER_STATUSES = [
  'pending_confirmation',
  'confirmed',
  'preparing',
  'ready_for_pickup',
  'completed',
  'cancelled',
] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const PRODUCT_REQUEST_STATUSES = ['active', 'closed'] as const;
export type ProductRequestStatus = (typeof PRODUCT_REQUEST_STATUSES)[number];

export const REPORT_STATUSES = ['open', 'reviewed', 'actioned'] as const;
export type ReportStatus = (typeof REPORT_STATUSES)[number];

/** Custom claims on the Firebase Auth ID token. Set only by trusted code. */
export interface AppClaims {
  student?: boolean;
  reviewer?: boolean;
  admin?: boolean;
  businessId?: string;
}

/** Display-only mirror of the claims, stored on users/{uid}. */
export interface RoleFlags {
  student: boolean;
  business: boolean;
  reviewer: boolean;
  admin: boolean;
}
