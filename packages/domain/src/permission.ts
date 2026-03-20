import type { SwiftDate } from "./types";

export const PERMISSION_TYPES = ["Allow", "Deny", "Require Approval"] as const;
export type PermissionType = (typeof PERMISSION_TYPES)[number];

export interface Permission {
  id: string;
  fromAgentID: string;
  toAgentID: string;
  permissionType: PermissionType;
  createdAt: SwiftDate;
  updatedAt: SwiftDate;
}
