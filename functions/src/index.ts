// Entry point: global options and the list of deployed functions.
// Each callable and trigger lives in its own module and is re-exported here;
// the export name is the deployed function name.
import { setGlobalOptions } from 'firebase-functions/v2';
import { MAX_INSTANCES, REGION } from './shared/config';

setGlobalOptions({ region: REGION, maxInstances: MAX_INSTANCES });

export { syncStudentStatus } from './callable/auth/syncStudentStatus';
export { setStaffRole } from './callable/admin/setStaffRole';
