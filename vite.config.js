import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import vue from '@vitejs/plugin-vue';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

export default defineConfig({
    server: {
        port: 3000,
        host: true,
        hmr: {
            host: process.env.VITE_HOT_HOST || 'localhost',
            protocol: 'ws'
        }
    },
    plugins: [
        laravel({
            input: 'resources/js/app.js',
            refresh: true,
        }),
        vue({
            template: {
                transformAssetUrls: {
                    base: null,
                    includeAbsolute: false,
                },
            },
        }),
    ],
});
