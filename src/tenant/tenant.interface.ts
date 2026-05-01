// src/tenant/tenant.interface.ts
export interface TenantContext {
  userId: string;
  organizationId: string;
  role: string;
  firebaseUid: string;
}
