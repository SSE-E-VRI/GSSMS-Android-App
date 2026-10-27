// src/shape.js
// Data shaping functions copied directly from GSSMS/frontend/src/views/StaffDashboardView.jsx
// with file:line citations for exact parity.

import { reportStatusLabel } from '../../../../GSSMS/frontend/src/utils/reportStatusLabel';
import { formatDate } from '../../../../GSSMS/frontend/src/utils/date';
import { toInspectionReport } from '../../../../GSSMS/frontend/src/components/reports/InspectionReportPreview';
import { toPhotoReport as toRectificationPhotoReport } from '../../../../GSSMS/frontend/src/components/reports/RectificationReportPreview';

/**
 * formatRecordedValue from StaffDashboardView.jsx lines 69-86
 */
export const formatRecordedValue = (val) => {
    if (!val) return '';
    try {
        let parsed = val;
        if (typeof val === 'string' && (val.startsWith('{') || val.startsWith('['))) {
            parsed = JSON.parse(val);
        }
        if (typeof parsed === 'object' && parsed !== null) {
            return Object.entries(parsed)
                .filter(([k, v]) => v !== null && v !== '')
                .map(([k, v]) => `${k}: ${v}`)
                .join(', ');
        }
        return parsed;
    } catch (e) {
        return val;
    }
};

/**
 * Checklist shaping from StaffDashboardView.jsx lines 314-395 and 803-818
 */
export const shapeChecklistData = (record, wo) => {
    const lines = record.lines || [];
    const groups = lines.reduce((acc, line) => {
        // StaffDashboardView.jsx lines 318-319:
        if (line.checked_out === false || line.excluded) return acc;
        const groupKey = line.asset_unique_id
            || `${line.asset_category_id ?? 'none'}::${(line.item_name || '').trim().toLowerCase()}`;
        if (!acc[groupKey]) acc[groupKey] = {
            group_name: line.asset_group_label_override || line.item_name || line.asset_category || 'General Items',
            items: [],
        };

        const isAddressed = Boolean(line.status_label_snapshot)
            || Boolean((line.observation_action || '').trim())
            || (line.recorded_value !== undefined && line.recorded_value !== null && line.recorded_value !== '')
            || (line.status && line.status !== 'OK');
        acc[groupKey].items.push({
            ...line,
            grading: line.status,
            status_label: reportStatusLabel({ snapshotLabel: line.status_label_snapshot, status: line.status, addressed: isAddressed }),
            action_label: line.action_label_snapshot || '',
            formattedValue: formatRecordedValue(line.recorded_value),
            remarks: line.observation_action || line.remarks
        });
        return acc;
    }, {});

    const groupArray = Object.values(groups);
    groupArray.forEach(group => {
        let currentItem = null;
        let currentSpanStart = null;
        group.items.forEach(item => {
            if (item.item_name !== currentItem) {
                currentItem = item.item_name;
                item.itemRowSpan = 1;
                currentSpanStart = item;
            } else {
                if (currentSpanStart) currentSpanStart.itemRowSpan++;
                item.itemRowSpan = 0;
            }
        });
    });

    const deficiencies = lines.map(line => {
        if (line.checked_out === false || line.excluded) return null;

        const selectedStatus = (line.status_options || []).find(
            option => String(option.id) === String(line.status_option)
        );
        const selectedAction = (selectedStatus?.action_options || []).find(
            option => String(option.id) === String(line.action_option)
        );
        if (!selectedStatus?.is_deficiency && !selectedAction?.is_deficiency) return null;

        return {
            id: line.id,
            asset: line.asset_unique_id || line.item_name || line.asset_category || 'General',
            checkpoint: line.inspection_point,
            finding: selectedStatus?.label || line.status_label_snapshot || '-',
            action: selectedAction?.label || line.action_label_snapshot || '-',
            severity: line.deficiency_severity_label || 'Pending review',
        };
    }).filter(Boolean);

    let station = wo.station_name || wo.depot_name || 'Unknown';
    if (record.schedule_details && record.schedule_details.station_name) station = record.schedule_details.station_name;

    const metadata = {
        stationName: station,
        date: formatDate(record.date_of_maintenance || wo.updated_at),
        schedule: record.schedule_details ? (record.schedule_details.template_name || "Scheduled Maintenance") : wo.title,
        technician: record.technician_name || wo.assigned_to_name || 'Unknown',
        verification: record.verification ?? null,
        remarks: record.remarks || '',
        otherStaff: record.other_staff || '',
        organization: record.schedule_details?.organization
    };

    return {
        groups: groupArray,
        deficiencies,
        metadata
    };
};

/**
 * Breakdown shaping from StaffDashboardView.jsx lines 260-264, 415-418, and 786-801
 */
export const shapeBreakdownData = (payload, wo, ticket) => {
    const execution = payload.submission_history?.at(-1) || payload;
    const metadata = {
        organization: payload.organization,
        verification: payload.verification,
        stationName: wo.station_name || wo.depot_name || 'Unknown',
        technician: wo.assigned_to_name || 'Unknown',
    };
    return {
        execution,
        metadata,
        workOrder: { ...wo, ticket_number: ticket }
    };
};

/**
 * Inspection shaping from StaffDashboardView.jsx lines 395-401, 408-413, and 770-775
 */
export const shapeInspectionData = (payload, ticket) => {
    const report = toInspectionReport(payload);
    const normalizedReport = report && !report.ticketNumber ? { ...report, ticketNumber: ticket } : report;
    return {
        inspectionReport: normalizedReport
    };
};

/**
 * Rectification shaping from StaffDashboardView.jsx lines 776-784
 */
export const shapeRectificationData = (payload, ticket, stationName) => {
    return {
        workOrder: { ticket_number: ticket, station_name: stationName },
        rectification: payload
    };
};

export { toRectificationPhotoReport };
