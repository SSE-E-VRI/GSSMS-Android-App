// apiStub.js
export default {
  get: async () => ({ data: new Blob() }),
  getRecords: async () => ({ data: [] }),
  getComplaintExecution: async () => ({ data: {} }),
  getInspectionExecution: async () => ({ data: {} }),
  getRectification: async () => ({ data: {} }),
};

export const fixFileUrl = (u) => u;
