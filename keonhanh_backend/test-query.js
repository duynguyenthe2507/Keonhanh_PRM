require('dotenv').config();
const sql = require('mssql');
const dbConfig = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    server: process.env.DB_SERVER,
    database: process.env.DB_NAME,
    options: { encrypt: false, trustServerCertificate: true }
};
sql.connect(dbConfig).then(async () => {
    try {
        const res = await sql.query("SELECT t.* FROM Teams t JOIN User_profiles p ON t.CaptainId = p.UserId WHERE p.Id = 'D0F24DA6-AE09-4DCF-9F14-E64F0C850052'");
        console.log("Recordset:");
        console.dir(res.recordset, { depth: null });
    } catch (e) {
        console.error(e);
    }
    process.exit(0);
});
