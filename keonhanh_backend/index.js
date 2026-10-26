require('dotenv').config();
const express = require('express');
const cors = require('cors');
const sql = require('mssql');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const app = express();
app.use(cors());
app.use(express.json());

const dbConfig = {
    user: process.env.DB_USER || 'sa',
    password: process.env.DB_PASSWORD || 'YourStrongPassword123!',
    server: process.env.DB_SERVER || 'localhost',
    database: process.env.DB_NAME || 'Keonhanh',
    options: { encrypt: false, trustServerCertificate: true }
};

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

// --- KẾT NỐI DATABASE ---
sql.connect(dbConfig).then(() => {
    console.log("✅ Đã kết nối tới SQL Server");
}).catch(err => {
    console.error("❌ Lỗi kết nối SQL Server:", err);
});

// --- AUTH ROUTER ---
app.post('/api/auth/register', async (req, res) => {
    try {
        const { username, password } = req.body;
        const hash = await bcrypt.hash(password, 10);
        
        const request = new sql.Request();
        request.input('user', sql.NVarChar, username);
        const check = await request.query("SELECT * FROM Users WHERE Username = @user");
        if (check.recordset.length > 0) return res.status(400).json({ success: false, message: 'Tài khoản đã tồn tại' });

        request.input('pass', sql.NVarChar, hash);
        await request.query("INSERT INTO Users (Username, Password) VALUES (@user, @pass)");
        res.json({ success: true, message: 'Đăng ký thành công' });
    } catch (e) {
        console.error(e);
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
});

app.post('/api/auth/login', async (req, res) => {
    try {
        const { username, password } = req.body;
        const request = new sql.Request();
        request.input('user', sql.NVarChar, username);
        const result = await request.query("SELECT * FROM Users WHERE Username = @user");
        
        if (result.recordset.length === 0) return res.status(401).json({ success: false, message: 'Sai tài khoản' });
        
        const user = result.recordset[0];
        const match = await bcrypt.compare(password, user.Password);
        if (!match) return res.status(401).json({ success: false, message: 'Sai mật khẩu' });

        const token = jwt.sign({ id: user.Id }, JWT_SECRET);
        res.json({
            success: true,
            token,
            user: { id: user.Id, username: user.Username, role: user.Role }
        });
    } catch (e) {
        console.error(e);
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
});

// --- USER PROFILES ---
app.get('/api/user-profiles/:userId', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('userId', sql.UniqueIdentifier, req.params.userId);
        const result = await request.query("SELECT * FROM User_profiles WHERE UserId = @userId");
        if (result.recordset.length > 0) {
            let record = result.recordset[0];
            let profile = {
                _id: record.Id,
                userId: record.UserId,
                phone: record.Phone,
                avatar: record.Avatar,
                fullName: record.FullName,
                position: record.Position,
                location: record.Location,
                isLookingForTeam: record.IsLookingForTeam
            };
            res.json({ success: true, profile });
        } else {
            res.json({ success: false, message: 'Chưa có profile' });
        }
    } catch (e) {
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
});

app.post('/api/user-profiles', async (req, res) => {
    try {
        const p = req.body;
        const request = new sql.Request();
        request.input('userId', sql.UniqueIdentifier, p.userId);
        request.input('phone', sql.NVarChar, p.phone);
        request.input('avatar', sql.NVarChar, p.avatar || '');
        request.input('fullName', sql.NVarChar, p.fullName);
        request.input('position', sql.NVarChar, p.position);
        request.input('location', sql.NVarChar, p.location);
        
        await request.query(`
            IF EXISTS(SELECT 1 FROM User_profiles WHERE UserId = @userId)
                UPDATE User_profiles SET Phone=@phone, Avatar=@avatar, FullName=@fullName, Position=@position, Location=@location WHERE UserId=@userId
            ELSE
                INSERT INTO User_profiles (UserId, Phone, Avatar, FullName, Position, Location) VALUES (@userId, @phone, @avatar, @fullName, @position, @location)
        `);
        res.json({ success: true, message: 'Cập nhật thành công' });
    } catch (e) {
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
});

// --- TEAMS ---
app.get('/api/teams', async (req, res) => {
    try {
        const result = await sql.query(`
            SELECT t.*, u.Username AS CaptainUsername, p.FullName AS CaptainFullName
            FROM Teams t
            LEFT JOIN Users u ON t.CaptainId = u.Id
            LEFT JOIN User_profiles p ON u.Id = p.UserId
        `);

        const teamIds = result.recordset.map(t => `'${t.Id}'`);
        let playersMap = {};

        if (teamIds.length > 0) {
            const teamIdsStr = teamIds.join(',');
            const playersQuery = `
                SELECT t.Id AS TeamId, p.Id AS _id
                FROM Teams t
                JOIN User_profiles p ON t.CaptainId = p.UserId
                WHERE t.Id IN (${teamIdsStr})
                UNION
                SELECT tp.TeamId, tp.UserProfileId AS _id
                FROM TeamPlayers tp
                WHERE tp.TeamId IN (${teamIdsStr})
            `;
            const playersResult = await sql.query(playersQuery);
            for (const p of playersResult.recordset) {
                if (!playersMap[p.TeamId]) playersMap[p.TeamId] = [];
                playersMap[p.TeamId].push({ _id: p._id });
            }
        }

        const data = result.recordset.map(t => {
            const capName = t.CaptainFullName || t.CaptainUsername || 'Ẩn danh';
            return {
                _id: t.Id, 
                name: t.Name, 
                logo: t.Logo, 
                level: t.SkillLevel, 
                skillLevel: t.SkillLevel, 
                location: t.Location,
                isRecruiting: t.IsRecruiting, 
                desc: '', 
                captainId: {
                    _id: t.CaptainId,
                    username: capName
                }, 
                captainName: capName,
                players: playersMap[t.Id] || []
            };
        });
        res.json({ success: true, data });
    } catch (e) {
        console.error('Error fetching teams:', e);
        res.json({ success: false, data: [] });
    }
});

app.post('/api/teams', async (req, res) => {
    try {
        const { name, logo, skillLevel, location, isRecruiting, captainId } = req.body;
        const request = new sql.Request();
        request.input('name', sql.NVarChar, name);
        request.input('logo', sql.NVarChar, logo || '');
        request.input('skillLevel', sql.NVarChar, skillLevel || 'Sơ cấp');
        request.input('location', sql.NVarChar, location);
        request.input('isRecruiting', sql.Bit, isRecruiting ? 1 : 0);
        request.input('captainId', sql.UniqueIdentifier, captainId); // Uses Users.Id directly

        await request.query(`
            INSERT INTO Teams (Name, Logo, SkillLevel, Location, IsRecruiting, CaptainId)
            VALUES (@name, @logo, @skillLevel, @location, @isRecruiting, @captainId);
            UPDATE User_profiles SET IsLookingForTeam = 0, UpdatedAt = GETDATE() WHERE UserId = @captainId;
        `);
        res.json({ success: true, message: 'Tạo đội thành công' });
    } catch (e) {
        console.error(e);
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
});

app.get('/api/teams/my-team/:profileId', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('profileId', sql.UniqueIdentifier, req.params.profileId);
        const result = await request.query(`
            SELECT DISTINCT t.*, u.Username AS CaptainUsername, p_cap.FullName AS CaptainFullName
            FROM Teams t
            LEFT JOIN Users u ON t.CaptainId = u.Id
            LEFT JOIN User_profiles p_cap ON u.Id = p_cap.UserId
            LEFT JOIN TeamPlayers tp ON t.Id = tp.TeamId
            WHERE t.CaptainId IN (SELECT UserId FROM User_profiles WHERE Id = @profileId)
               OR tp.UserProfileId = @profileId
        `);

        const teamIds = result.recordset.map(t => `'${t.Id}'`);
        let playersMap = {};

        if (teamIds.length > 0) {
            const teamIdsStr = teamIds.join(',');
            const playersQuery = `
                -- Captain profile
                SELECT t.Id AS TeamId, p.Id AS _id, p.FullName AS fullName, p.Position AS position, 
                       p.Location AS location, p.Phone AS phone, p.Avatar AS avatar, p.UserId AS userId, 1 AS isCaptain
                FROM Teams t
                JOIN User_profiles p ON t.CaptainId = p.UserId
                WHERE t.Id IN (${teamIdsStr})
                UNION
                -- Team members
                SELECT tp.TeamId, p.Id AS _id, p.FullName AS fullName, p.Position AS position, 
                       p.Location AS location, p.Phone AS phone, p.Avatar AS avatar, p.UserId AS userId, 0 AS isCaptain
                FROM TeamPlayers tp
                JOIN User_profiles p ON tp.UserProfileId = p.Id
                WHERE tp.TeamId IN (${teamIdsStr})
            `;
            const playersResult = await sql.query(playersQuery);
            for (const p of playersResult.recordset) {
                if (!playersMap[p.TeamId]) playersMap[p.TeamId] = [];
                playersMap[p.TeamId].push({
                    _id: p._id,
                    fullName: p.fullName,
                    position: p.position,
                    location: p.location,
                    phone: p.phone,
                    avatar: p.avatar,
                    userId: p.userId
                });
            }
        }

        const data = result.recordset.map(t => {
            const capName = t.CaptainFullName || t.CaptainUsername || 'Ẩn danh';
            return {
                _id: t.Id, 
                name: t.Name, 
                logo: t.Logo, 
                level: t.SkillLevel, 
                skillLevel: t.SkillLevel, 
                location: t.Location,
                isRecruiting: t.IsRecruiting, 
                desc: '', 
                captainId: {
                    _id: t.CaptainId,
                    username: capName
                }, 
                captainName: capName,
                players: playersMap[t.Id] || []
            };
        });
        res.json({ success: true, data });
    } catch (e) {
        console.error('Error fetching my-team:', e);
        res.json({ success: false, data: [] });
    }
});

// --- MATCHES ---
app.get('/api/matches', async (req, res) => {
    try {
        const result = await sql.query(`
            SELECT m.*, t.Name AS TeamName 
            FROM Matches m 
            LEFT JOIN Teams t ON m.CreatorTeamId = t.Id
        `);
        const data = result.recordset.map(m => ({
            _id: m.Id, status: m.Status, playTime: m.PlayTime, fieldName: m.FieldName,
            creatorTeamId: { name: m.TeamName || 'Đội ẩn danh' }
        }));
        res.json({ success: true, data });
    } catch (e) {
        res.json({ success: false, data: [] });
    }
});

app.post('/api/matches', async (req, res) => {
    try {
        const { userId, playTime, fieldName, location, latitude, longitude } = req.body;
        const request = new sql.Request();
        request.input('userId', sql.UniqueIdentifier, userId);

        const teamRes = await request.query(`
            SELECT TOP 1 Id 
            FROM Teams 
            WHERE CaptainId = @userId
        `);
        
        if (teamRes.recordset.length === 0) {
            return res.status(400).json({ success: false, message: 'Bạn phải tạo đội bóng trước khi đăng kèo!' });
        }
        const teamId = teamRes.recordset[0].Id;

        request.input('teamId', sql.UniqueIdentifier, teamId);
        request.input('playTime', sql.DateTime, new Date(playTime));
        request.input('fieldName', sql.NVarChar, fieldName);
        request.input('location', sql.NVarChar, location || '');
        request.input('latitude', sql.Float, latitude || null);
        request.input('longitude', sql.Float, longitude || null);

        await request.query(`
            INSERT INTO Matches (CreatorTeamId, PlayTime, FieldName, Location, Latitude, Longitude)
            VALUES (@teamId, @playTime, @fieldName, @location, @latitude, @longitude)
        `);
        res.json({ success: true, message: 'Tạo kèo thành công' });
    } catch (e) {
        console.error(e);
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
});

// --- PLAYERS ---
app.get('/api/players', async (req, res) => {
    try {
        const result = await sql.query("SELECT * FROM User_profiles");
        const data = result.recordset.map(p => ({
            _id: p.Id, 
            userId: p.UserId,
            fullName: p.FullName, 
            position: p.Position, 
            location: p.Location, 
            phone: p.Phone, 
            avatar: p.Avatar, 
            isLookingForTeam: p.IsLookingForTeam
        }));
        res.json({ success: true, players: data });
    } catch (e) {
        res.json({ success: false, players: [] });
    }
});

app.get('/api/matches/my-matches/:teamId', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('teamId', sql.UniqueIdentifier, req.params.teamId);
        const result = await request.query(`
            SELECT m.*, 
                   t.Name AS CreatorTeamName, t.Logo AS CreatorTeamLogo,
                   t2.Name AS MatchedTeamName, t2.Logo AS MatchedTeamLogo 
            FROM Matches m 
            LEFT JOIN Teams t ON m.CreatorTeamId = t.Id
            LEFT JOIN Teams t2 ON m.MatchedWithTeamId = t2.Id
            WHERE m.CreatorTeamId = @teamId OR m.MatchedWithTeamId = @teamId
            ORDER BY m.PlayTime ASC
        `);
        const data = result.recordset.map(m => ({
            _id: m.Id, 
            status: m.Status, 
            playTime: m.PlayTime, 
            fieldName: m.FieldName,
            location: m.Location,
            creatorTeamId: { _id: m.CreatorTeamId, name: m.CreatorTeamName || 'Đội ẩn danh', logo: m.CreatorTeamLogo },
            matchedWithTeamId: m.MatchedWithTeamId ? { _id: m.MatchedWithTeamId, name: m.MatchedTeamName || 'Đội ẩn danh', logo: m.MatchedTeamLogo } : null
        }));
        res.json({ success: true, data });
    } catch (e) {
        console.error('Error fetching my-matches:', e);
        res.json({ success: false, data: [] });
    }
});

app.get('/api/matches/:id', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, req.params.id);
        const result = await request.query(`
            SELECT m.*, 
                   t.Name AS CreatorTeamName, t.Logo AS CreatorTeamLogo,
                   t2.Name AS MatchedTeamName, t2.Logo AS MatchedTeamLogo
            FROM Matches m 
            LEFT JOIN Teams t ON m.CreatorTeamId = t.Id
            LEFT JOIN Teams t2 ON m.MatchedWithTeamId = t2.Id
            WHERE m.Id = @id
        `);
        if (result.recordset.length === 0) return res.status(404).json({ success: false, message: 'Không tìm thấy kèo' });
        const m = result.recordset[0];
        const data = {
            _id: m.Id, 
            status: m.Status, 
            playTime: m.PlayTime, 
            fieldName: m.FieldName, 
            fieldAddress: m.Location,
            location: m.Location,
            creatorTeamId: { _id: m.CreatorTeamId, name: m.CreatorTeamName || 'Đội ẩn danh', logo: m.CreatorTeamLogo },
            matchedWithTeamId: m.MatchedWithTeamId ? { _id: m.MatchedWithTeamId, name: m.MatchedTeamName || 'Đội ẩn danh', logo: m.MatchedTeamLogo } : null
        };
        res.json({ success: true, data, ...data });
    } catch (e) {
        console.error('Error fetching match by id:', e);
        res.status(500).json({ success: false });
    }
});

app.patch('/api/matches/:id/match', async (req, res) => {
    try {
        const { id } = req.params;
        const { matchedWithTeamId, userId } = req.body;

        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, id);
        const matchRes = await request.query("SELECT * FROM Matches WHERE Id = @id");
        if (matchRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy trận đấu" });
        }

        const match = matchRes.recordset[0];
        if (match.Status !== 'open') {
            return res.status(400).json({ success: false, message: "Trận đấu đã được ghép hoặc đã hủy" });
        }

        if (match.CreatorTeamId.toLowerCase() === matchedWithTeamId.toLowerCase()) {
            return res.status(400).json({ success: false, message: "Không thể nhận kèo của chính đội mình" });
        }

        const teamReq = new sql.Request();
        teamReq.input('teamId', sql.UniqueIdentifier, matchedWithTeamId);
        const teamRes = await teamReq.query("SELECT * FROM Teams WHERE Id = @teamId");
        if (teamRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy đội bóng" });
        }
        const team = teamRes.recordset[0];
        if (team.CaptainId.toLowerCase() !== userId.toLowerCase()) {
            return res.status(403).json({ success: false, message: "Chỉ đội trưởng mới có quyền nhận kèo" });
        }

        const updateReq = new sql.Request();
        updateReq.input('id', sql.UniqueIdentifier, id);
        updateReq.input('matchedWithTeamId', sql.UniqueIdentifier, matchedWithTeamId);
        await updateReq.query(`
            UPDATE Matches 
            SET MatchedWithTeamId = @matchedWithTeamId, Status = 'matched', UpdatedAt = GETDATE()
            WHERE Id = @id
        `);

        res.json({ success: true, message: "Nhận kèo thành công" });
    } catch (e) {
        console.error('Error matching team:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.patch('/api/matches/:id/cancel', async (req, res) => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, id);
        const matchRes = await request.query(`
            SELECT m.*, t.CaptainId AS CreatorCaptainId, t2.CaptainId AS MatchedCaptainId
            FROM Matches m
            LEFT JOIN Teams t ON m.CreatorTeamId = t.Id
            LEFT JOIN Teams t2 ON m.MatchedWithTeamId = t2.Id
            WHERE m.Id = @id
        `);
        if (matchRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy trận đấu" });
        }

        const match = matchRes.recordset[0];
        if (match.Status !== 'matched') {
            return res.status(400).json({ success: false, message: "Trận đấu không ở trạng thái có thể hủy ghép" });
        }

        const isCreatorCap = match.CreatorCaptainId && match.CreatorCaptainId.toLowerCase() === userId.toLowerCase();
        const isMatchedCap = match.MatchedCaptainId && match.MatchedCaptainId.toLowerCase() === userId.toLowerCase();
        if (!isCreatorCap && !isMatchedCap) {
            return res.status(403).json({ success: false, message: "Chỉ đội trưởng của 2 đội mới có quyền hủy kèo" });
        }

        await request.query(`
            UPDATE Matches 
            SET MatchedWithTeamId = NULL, Status = 'open', UpdatedAt = GETDATE()
            WHERE Id = @id
        `);

        res.json({ success: true, message: "Hủy kèo thành công" });
    } catch (e) {
        console.error('Error cancelling match:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.delete('/api/matches/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, id);
        await request.query("DELETE FROM Matches WHERE Id = @id");
        res.json({ success: true, message: "Xóa trận đấu thành công" });
    } catch (e) {
        console.error('Error deleting match:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.get('/api/join-requests/captain/:userId', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('userId', sql.UniqueIdentifier, req.params.userId);
        const result = await request.query(`
            SELECT jr.*, p.FullName, p.Position, p.Avatar, p.Location, p.Phone
            FROM JoinRequests jr
            JOIN User_profiles p ON jr.RequesterId = p.Id
            JOIN Teams t ON jr.TeamId = t.Id
            WHERE t.CaptainId = @userId AND jr.Status = 'pending'
        `);
        const data = result.recordset.map(r => ({
            _id: r.Id, 
            status: r.Status, 
            requesterId: { 
                _id: r.RequesterId, 
                fullName: r.FullName, 
                position: r.Position, 
                avatar: r.Avatar,
                location: r.Location,
                phone: r.Phone
            },
            teamId: r.TeamId
        }));
        res.json({ success: true, data });
    } catch (e) {
        console.error('Error fetching captain join requests:', e);
        res.json({ success: false, data: [] });
    }
});

app.get('/api/join-requests/player/:profileId', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('profileId', sql.UniqueIdentifier, req.params.profileId);
        const result = await request.query(`
            SELECT jr.*, t.Name AS TeamName, t.Location AS TeamLocation, t.CaptainId, u.Username AS CaptainUsername, p.FullName AS CaptainFullName
            FROM JoinRequests jr
            LEFT JOIN Teams t ON jr.TeamId = t.Id
            LEFT JOIN Users u ON t.CaptainId = u.Id
            LEFT JOIN User_profiles p ON u.Id = p.UserId
            WHERE jr.RequesterId = @profileId
        `);
        const data = result.recordset.map(r => {
            const capName = r.CaptainFullName || r.CaptainUsername || 'Ẩn danh';
            return {
                _id: r.Id, 
                status: r.Status, 
                teamId: { 
                    _id: r.TeamId,
                    name: r.TeamName || '',
                    location: r.TeamLocation || '',
                    captainId: {
                        _id: r.CaptainId,
                        username: capName
                    }
                }
            };
        });
        res.json({ success: true, data });
    } catch (e) {
        console.error('Error in /api/join-requests/player:', e);
        res.json({ success: false, data: [] });
    }
});

app.post('/api/join-requests', async (req, res) => {
    try {
        const { teamId, requesterId } = req.body;
        const request = new sql.Request();
        request.input('teamId', sql.UniqueIdentifier, teamId);
        request.input('requesterId', sql.UniqueIdentifier, requesterId);
        await request.query("INSERT INTO JoinRequests (TeamId, RequesterId) VALUES (@teamId, @requesterId)");
        res.json({ success: true, message: 'Đã gửi yêu cầu' });
    } catch (e) {
        res.json({ success: false, message: 'Lỗi' });
    }
});

app.patch('/api/join-requests/:id/approve', async (req, res) => {
    try {
        const { id } = req.params;
        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, id);

        const checkRes = await request.query("SELECT * FROM JoinRequests WHERE Id = @id");
        if (checkRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy yêu cầu." });
        }

        const joinReq = checkRes.recordset[0];
        if (joinReq.Status !== 'pending') {
            return res.status(400).json({ success: false, message: "Yêu cầu này đã được xử lý rồi." });
        }

        const teamId = joinReq.TeamId;
        const requesterId = joinReq.RequesterId;

        // Kiểm tra cầu thủ đã tham gia đội nào chưa
        const teamCheckReq = new sql.Request();
        teamCheckReq.input('requesterId', sql.UniqueIdentifier, requesterId);
        const inTeamRes = await teamCheckReq.query("SELECT 1 FROM TeamPlayers WHERE UserProfileId = @requesterId");
        if (inTeamRes.recordset.length > 0) {
            const updateReq = new sql.Request();
            updateReq.input('id', sql.UniqueIdentifier, id);
            await updateReq.query("UPDATE JoinRequests SET Status = 'rejected', UpdatedAt = GETDATE() WHERE Id = @id");
            return res.status(400).json({ success: false, message: "Cầu thủ này đã gia nhập một đội khác." });
        }

        // Thêm vào bảng TeamPlayers
        const addPlayerReq = new sql.Request();
        addPlayerReq.input('teamId', sql.UniqueIdentifier, teamId);
        addPlayerReq.input('requesterId', sql.UniqueIdentifier, requesterId);
        await addPlayerReq.query(`
            IF NOT EXISTS (SELECT 1 FROM TeamPlayers WHERE TeamId = @teamId AND UserProfileId = @requesterId)
            BEGIN
                INSERT INTO TeamPlayers (TeamId, UserProfileId) VALUES (@teamId, @requesterId);
            END
        `);

        // Kiểm tra số lượng thành viên (>= 14 người thì tự động khóa tuyển)
        const countReq = new sql.Request();
        countReq.input('teamId', sql.UniqueIdentifier, teamId);
        const countRes = await countReq.query("SELECT COUNT(*) AS total FROM TeamPlayers WHERE TeamId = @teamId");
        if (countRes.recordset[0].total >= 13) {
            await countReq.query("UPDATE Teams SET IsRecruiting = 0, RecruitingStatus = 'Full', UpdatedAt = GETDATE() WHERE Id = @teamId");
        }

        // Cập nhật UserProfile: IsLookingForTeam = 0
        const profileReq = new sql.Request();
        profileReq.input('requesterId', sql.UniqueIdentifier, requesterId);
        await profileReq.query("UPDATE User_profiles SET IsLookingForTeam = 0, UpdatedAt = GETDATE() WHERE Id = @requesterId");

        // Cập nhật trạng thái JoinRequest hiện tại thành approved
        const approveReq = new sql.Request();
        approveReq.input('id', sql.UniqueIdentifier, id);
        approveReq.input('requesterId', sql.UniqueIdentifier, requesterId);
        await approveReq.query(`
            UPDATE JoinRequests SET Status = 'approved', UpdatedAt = GETDATE() WHERE Id = @id;
            UPDATE JoinRequests SET Status = 'rejected', UpdatedAt = GETDATE() WHERE RequesterId = @requesterId AND Status = 'pending' AND Id <> @id;
        `);

        res.json({ success: true, message: "Đã phê duyệt thành viên vào đội." });
    } catch (e) {
        console.error('Error approving join request:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.patch('/api/join-requests/:id/reject', async (req, res) => {
    try {
        const { id } = req.params;
        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, id);

        const checkRes = await request.query("SELECT * FROM JoinRequests WHERE Id = @id");
        if (checkRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy yêu cầu." });
        }

        const joinReq = checkRes.recordset[0];
        if (joinReq.Status !== 'pending') {
            return res.status(400).json({ success: false, message: "Yêu cầu này đã được xử lý rồi." });
        }

        await request.query("UPDATE JoinRequests SET Status = 'rejected', UpdatedAt = GETDATE() WHERE Id = @id");
        res.json({ success: true, message: "Đã từ chối yêu cầu gia nhập." });
    } catch (e) {
        console.error('Error rejecting join request:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.patch('/api/teams/:teamId/kick/:profileId', async (req, res) => {
    try {
        const { teamId, profileId } = req.params;
        const request = new sql.Request();
        request.input('teamId', sql.UniqueIdentifier, teamId);
        request.input('profileId', sql.UniqueIdentifier, profileId);

        const capCheck = await request.query(`
            SELECT t.CaptainId, p.Id AS CaptainProfileId
            FROM Teams t
            JOIN User_profiles p ON t.CaptainId = p.UserId
            WHERE t.Id = @teamId
        `);
        if (capCheck.recordset.length > 0 && capCheck.recordset[0].CaptainProfileId.toLowerCase() === profileId.toLowerCase()) {
            return res.status(400).json({ success: false, message: "Không thể kick đội trưởng." });
        }

        await request.query(`
            DELETE FROM TeamPlayers WHERE TeamId = @teamId AND UserProfileId = @profileId;
            UPDATE User_profiles SET IsLookingForTeam = 1, UpdatedAt = GETDATE() WHERE Id = @profileId;
        `);

        res.json({ success: true, message: "Đã xóa thành viên khỏi đội." });
    } catch (e) {
        console.error('Error kicking player:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.patch('/api/teams/:teamId/toggle-recruiting', async (req, res) => {
    try {
        const { teamId } = req.params;
        const { captainUserId } = req.body;

        const request = new sql.Request();
        request.input('teamId', sql.UniqueIdentifier, teamId);
        const result = await request.query("SELECT * FROM Teams WHERE Id = @teamId");
        if (result.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy đội bóng." });
        }

        const team = result.recordset[0];
        if (captainUserId && team.CaptainId.toLowerCase() !== captainUserId.toLowerCase()) {
            return res.status(403).json({ success: false, message: "Chỉ đội trưởng mới có thể thao tác này." });
        }

        const newIsRecruiting = team.IsRecruiting ? 0 : 1;
        const newStatus = newIsRecruiting ? 'Searching' : 'Full';

        const updateReq = new sql.Request();
        updateReq.input('teamId', sql.UniqueIdentifier, teamId);
        updateReq.input('isRecruiting', sql.Bit, newIsRecruiting);
        updateReq.input('recruitingStatus', sql.NVarChar, newStatus);
        await updateReq.query(`
            UPDATE Teams 
            SET IsRecruiting = @isRecruiting, RecruitingStatus = @recruitingStatus, UpdatedAt = GETDATE()
            WHERE Id = @teamId
        `);

        res.json({
            success: true,
            isRecruiting: newIsRecruiting === 1,
            message: newIsRecruiting === 1
                ? "Đã mở lại tuyển thành viên."
                : "Đã dừng tuyển thành viên. Người khác sẽ không thể gửi yêu cầu gia nhập."
        });
    } catch (e) {
        console.error('Error toggling recruiting:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.post('/api/invitations', async (req, res) => {
    try {
        const { teamId, playerProfileId, captainUserId } = req.body;
        if (!teamId || !playerProfileId || !captainUserId) {
            return res.status(400).json({ success: false, message: "Thiếu thông tin mời cầu thủ." });
        }

        // 1. Kiểm tra đội bóng và quyền đội trưởng
        const teamReq = new sql.Request();
        teamReq.input('teamId', sql.UniqueIdentifier, teamId);
        const teamRes = await teamReq.query("SELECT * FROM Teams WHERE Id = @teamId");
        if (teamRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy đội bóng." });
        }

        const team = teamRes.recordset[0];
        if (team.CaptainId.toString().toLowerCase() !== captainUserId.toString().toLowerCase()) {
            return res.status(403).json({ success: false, message: "Chỉ đội trưởng mới có quyền mời cầu thủ vào đội." });
        }

        // 2. Lấy thông tin cầu thủ được mời
        const playerReq = new sql.Request();
        playerReq.input('profileId', sql.UniqueIdentifier, playerProfileId);
        const playerRes = await playerReq.query("SELECT * FROM User_profiles WHERE Id = @profileId");
        if (playerRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: "Không tìm thấy hồ sơ cầu thủ." });
        }

        const playerProfile = playerRes.recordset[0];
        const targetUserId = playerProfile.UserId;

        // 3. Không thể tự mời chính mình!
        if (targetUserId.toString().toLowerCase() === captainUserId.toString().toLowerCase()) {
            return res.status(400).json({ success: false, message: "Bạn là đội trưởng, không thể tự mời chính mình vào đội!" });
        }

        // 4. Kiểm tra xem cầu thủ đã ở trong đội này chưa
        const inTeamReq = new sql.Request();
        inTeamReq.input('teamId', sql.UniqueIdentifier, teamId);
        inTeamReq.input('profileId', sql.UniqueIdentifier, playerProfileId);
        const inTeamRes = await inTeamReq.query("SELECT 1 FROM TeamPlayers WHERE TeamId = @teamId AND UserProfileId = @profileId");
        if (inTeamRes.recordset.length > 0) {
            return res.status(400).json({ success: false, message: "Cầu thủ này đã là thành viên trong đội của bạn." });
        }

        // 5. Kiểm tra xem đã gửi lời mời đang chờ duyệt chưa
        const existReq = new sql.Request();
        existReq.input('teamId', sql.UniqueIdentifier, teamId);
        existReq.input('userId', sql.UniqueIdentifier, targetUserId);
        const existRes = await existReq.query("SELECT 1 FROM Invitations WHERE TeamId = @teamId AND UserId = @userId AND Status = 'pending'");
        if (existRes.recordset.length > 0) {
            return res.status(400).json({ success: false, message: "Bạn đã gửi lời mời cho cầu thủ này rồi, đang chờ phản hồi." });
        }

        // 6. Gửi lời mời mới
        const insertReq = new sql.Request();
        insertReq.input('teamId', sql.UniqueIdentifier, teamId);
        insertReq.input('userId', sql.UniqueIdentifier, targetUserId);
        await insertReq.query(`
            INSERT INTO Invitations (TeamId, UserId, Status, CreatedAt, UpdatedAt)
            VALUES (@teamId, @userId, 'pending', GETDATE(), GETDATE())
        `);

        res.json({ success: true, message: "Đã gửi lời mời tham gia đội bóng thành công!" });
    } catch (e) {
        console.error('Error creating invitation:', e);
        res.status(500).json({ success: false, message: "Lỗi server: " + e.message });
    }
});

app.get('/api/invitations/user/:userId', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('userId', sql.UniqueIdentifier, req.params.userId);
        const result = await request.query(`
            SELECT i.Id AS _id, i.Status AS status, i.CreatedAt AS createdAt,
                   t.Id AS teamId, t.Name AS teamName, t.Logo AS teamLogo, t.Location AS teamLocation,
                   u.Username AS captainUsername, p.FullName AS captainFullName
            FROM Invitations i
            JOIN Teams t ON i.TeamId = t.Id
            JOIN Users u ON t.CaptainId = u.Id
            LEFT JOIN User_profiles p ON u.Id = p.UserId
            WHERE i.UserId = @userId AND i.Status = 'pending'
            ORDER BY i.CreatedAt DESC
        `);

        const data = result.recordset.map(row => ({
            _id: row._id,
            status: row.status,
            createdAt: row.createdAt,
            teamId: {
                _id: row.teamId,
                name: row.teamName,
                logo: row.teamLogo,
                location: row.teamLocation,
            },
            captainId: {
                username: row.captainFullName || row.captainUsername || 'Đội trưởng',
            }
        }));

        res.json({ success: true, data });
    } catch (e) {
        console.error('Error fetching invitations:', e);
        res.json({ success: false, data: [] });
    }
});

app.patch('/api/invitations/:id/accept', async (req, res) => {
    try {
        const { id } = req.params;
        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, id);
        const invRes = await request.query("SELECT * FROM Invitations WHERE Id = @id");
        if (invRes.recordset.length === 0) return res.status(404).json({ success: false, message: "Không tìm thấy lời mời" });

        const inv = invRes.recordset[0];
        const profReq = new sql.Request();
        profReq.input('userId', sql.UniqueIdentifier, inv.UserId);
        const profRes = await profReq.query("SELECT Id FROM User_profiles WHERE UserId = @userId");
        if (profRes.recordset.length > 0) {
            const profileId = profRes.recordset[0].Id;
            const addReq = new sql.Request();
            addReq.input('teamId', sql.UniqueIdentifier, inv.TeamId);
            addReq.input('profileId', sql.UniqueIdentifier, profileId);
            await addReq.query(`
                IF NOT EXISTS (SELECT 1 FROM TeamPlayers WHERE TeamId = @teamId AND UserProfileId = @profileId)
                BEGIN
                    INSERT INTO TeamPlayers (TeamId, UserProfileId) VALUES (@teamId, @profileId);
                END
                UPDATE User_profiles SET IsLookingForTeam = 0, UpdatedAt = GETDATE() WHERE Id = @profileId;
            `);
        }
        await request.query("UPDATE Invitations SET Status = 'accepted', UpdatedAt = GETDATE() WHERE Id = @id");
        res.json({ success: true, message: "Đã tham gia đội bóng" });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

app.patch('/api/invitations/:id/reject', async (req, res) => {
    try {
        const { id } = req.params;
        const request = new sql.Request();
        request.input('id', sql.UniqueIdentifier, id);
        await request.query("UPDATE Invitations SET Status = 'rejected', UpdatedAt = GETDATE() WHERE Id = @id");
        res.json({ success: true, message: "Đã từ chối lời mời" });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

app.get('/api/invitations/me', (req, res) => res.json({ success: true, data: [] }));

app.get('/api/messages/:teamId', async (req, res) => {
    try {
        const request = new sql.Request();
        request.input('teamId', sql.UniqueIdentifier, req.params.teamId);
        const result = await request.query(`
            SELECT m.*, p.FullName, p.Avatar 
            FROM Messages m
            JOIN Users u ON m.SenderId = u.Id
            JOIN User_profiles p ON u.Id = p.UserId
            WHERE m.TeamId = @teamId
            ORDER BY m.CreatedAt ASC
        `);
        const data = result.recordset.map(m => ({
            _id: m.Id, content: m.Content, createdAt: m.CreatedAt,
            senderId: { _id: m.SenderId, fullName: m.FullName, avatar: m.Avatar }
        }));
        res.json(data);
    } catch (e) {
        res.json([]);
    }
});

app.post('/api/messages', async (req, res) => {
    try {
        const { teamId, senderId, content } = req.body;
        const request = new sql.Request();
        request.input('teamId', sql.UniqueIdentifier, teamId);
        request.input('senderId', sql.UniqueIdentifier, senderId);
        request.input('content', sql.NVarChar, content);
        await request.query("INSERT INTO Messages (TeamId, SenderId, Content) VALUES (@teamId, @senderId, @content)");
        res.json({ success: true });
    } catch (e) {
        res.json({ success: false });
    }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`🚀 Backend đang chạy tại http://localhost:${port}`));
