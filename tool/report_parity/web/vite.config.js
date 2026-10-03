import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const stubPath = path.resolve(__dirname, 'src/apiStub.js').replace(/\\/g, '/');

export default defineConfig({
  plugins: [react()],
  publicDir: path.resolve(__dirname, '../fixtures/public'),
  server: {
    fs: {
      allow: [path.resolve(__dirname, '../../../')],
    },
  },
  resolve: {
    alias: [
      {
        find: 'react',
        replacement: path.resolve(__dirname, 'node_modules/react'),
      },
      {
        find: 'react-dom',
        replacement: path.resolve(__dirname, 'node_modules/react-dom'),
      },
      {
        find: /.*\/services\/api(\.js)?$/,
        replacement: stubPath,
      },
    ],
  },
});
