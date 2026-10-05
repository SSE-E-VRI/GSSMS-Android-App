import React, { useEffect, useState, useRef } from 'react';
import { createRoot } from 'react-dom/client';
import { createPortal } from 'react-dom';

// Import CSS in the exact order as GSSMS/frontend/src/main.jsx:6-10
import 'bootstrap/dist/css/bootstrap.min.css';
import '../../../../GSSMS/frontend/src/style.css';
import '../../../../GSSMS/frontend/src/assets/iot-industrial-theme.css';

// Components
import FormPreview from '../../../../GSSMS/frontend/src/components/reports/FormPreview';
import ComplaintExecutionPrintPreview from '../../../../GSSMS/frontend/src/components/reports/ComplaintExecutionPrintPreview';
import InspectionReportPreview from '../../../../GSSMS/frontend/src/components/reports/InspectionReportPreview';
import RectificationReportPreview from '../../../../GSSMS/frontend/src/components/reports/RectificationReportPreview';

// Shaping helpers
import {
  shapeChecklistData,
  shapeBreakdownData,
  shapeInspectionData,
  shapeRectificationData,
} from './shape';
import { formatDate } from '../../../../GSSMS/frontend/src/utils/date';

const fixtures = import.meta.glob('../../fixtures/*.json', { eager: true });

function App() {
  const [reportReady, setReportReady] = useState(false);
  const containerRef = useRef(null);

  const params = new URLSearchParams(window.location.search);
  const fixtureId = params.get('fixture') || 'checklist_pm_full';
  const fixtureKey = `../../fixtures/${fixtureId}.json`;
  const fixture = fixtures[fixtureKey]?.default || fixtures[fixtureKey];

  useEffect(() => {
    if (!fixture) return;

    // Check when all images in #dash-print-container are loaded
    const checkImages = () => {
      const container = document.getElementById('dash-print-container');
      if (!container) return false;
      const images = Array.from(container.querySelectorAll('img'));
      const allLoaded = images.every((img) => img.complete && img.naturalHeight !== 0);
      return allLoaded;
    };

    const interval = setInterval(() => {
      if (checkImages()) {
        clearInterval(interval);
        window.__REPORT_READY__ = true;
        setReportReady(true);
      }
    }, 50);

    // Safety timeout in case there are no images
    const timeout = setTimeout(() => {
      window.__REPORT_READY__ = true;
      setReportReady(true);
      clearInterval(interval);
    }, 1000);

    return () => {
      clearInterval(interval);
      clearTimeout(timeout);
    };
  }, [fixture]);

  if (!fixture) {
    return <div>Fixture not found: {fixtureId}</div>;
  }

  const { kind, payload, workOrder, ticket } = fixture;

  let reportElement = null;

  if (kind === 'checklist' || kind === 'register') {
    const { groups, deficiencies, metadata } = shapeChecklistData(payload, workOrder);
    // Register export (ReportsView.jsx:454-467): the Job Work number is
    // shown and the completion date wins over date_of_maintenance.
    const registerMeta =
      kind === 'register'
        ? {
            ...metadata,
            date: formatDate(workOrder.report_completed_at || payload.date_of_maintenance),
            jobWorkNumber: workOrder.ticket_number,
          }
        : {};
    reportElement = (
      <FormPreview
        data={groups}
        stationName={metadata.stationName}
        date={registerMeta.date || metadata.date}
        schedule={metadata.schedule}
        organization={metadata.organization}
        technician={metadata.technician}
        verification={metadata.verification}
        remarks={metadata.remarks}
        otherStaff={metadata.otherStaff}
        deficiencies={deficiencies}
        jobWorkNumber={registerMeta.jobWorkNumber}
      />
    );
  } else if (kind === 'complaint') {
    const { execution, metadata, workOrder: wo } = shapeBreakdownData(payload, workOrder, ticket);
    reportElement = (
      <ComplaintExecutionPrintPreview
        workOrder={wo}
        execution={execution}
        metadata={metadata}
        photoCache={{ current: {} }}
      />
    );
  } else if (kind === 'inspection') {
    const { inspectionReport } = shapeInspectionData(payload, ticket);
    reportElement = (
      <InspectionReportPreview
        report={inspectionReport}
        photoCache={{ current: {} }}
      />
    );
  } else if (kind === 'rectification') {
    const stationName = workOrder.station_name || undefined;
    const { workOrder: wo, rectification } = shapeRectificationData(payload, ticket, stationName);
    reportElement = (
      <RectificationReportPreview
        workOrder={wo}
        rectification={rectification}
        photoCache={{ current: {} }}
      />
    );
  }

  // Exact print CSS from StaffDashboardView.jsx:451-467
  return (
    <>
      <style>
        {`
        @media print {
            body > *:not(#dash-print-container) { display: none !important; }
            body > #dash-print-container {
                display: block !important;
                position: absolute;
                left: 0;
                top: 0;
                width: 100%;
                margin: 0;
                padding: 0;
                background: white;
                z-index: 9999;
            }
        }
        /* For headless browser page.pdf, render #dash-print-container directly */
        #dash-print-container {
            display: block;
            background: white;
        }
        `}
      </style>
      {createPortal(
        <div id="dash-print-container" ref={containerRef}>
          {reportElement}
        </div>,
        document.body
      )}
    </>
  );
}

const root = createRoot(document.getElementById('root'));
root.render(<App />);
