// bcryptjs resolves via the image's NODE_PATH (/usr/src/node-red/node_modules)
const bcrypt = require('bcryptjs');
const adminPassword = process.env.NODE_RED_ADMIN_PASSWORD;

module.exports = {
    uiPort: process.env.PORT || 1880,
    flowFile: 'flows.json',
    flowFilePretty: true,
    credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET,
    userDir: '/data/',
    functionGlobalContext: {},

    adminAuth: adminPassword ? {
        type: 'credentials',
        users: [{
            username: process.env.NODE_RED_ADMIN_USER || 'admin',
            password: bcrypt.hashSync(adminPassword, 8),
            permissions: '*'
        }]
    } : undefined,

    logging: {
        console: {
            level: 'info',
            metrics: false,
            audit: false
        }
    },
    editorTheme: {
        projects: {
            enabled: false
        }
    }
}
