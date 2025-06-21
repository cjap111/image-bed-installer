#!/bin/bash

# 设置脚本在遇到错误时立即退出
set -e

# 日志文件
LOG_FILE="/var/log/image_bed_install.log"

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
    log_message "错误：请以root用户或使用sudo运行此脚本。"
    exit 1
fi

log_message "--- 图床一键安装脚本开始 ---"
log_message "本脚本将安装 Node.js, Nginx, Certbot, PM2，并部署图床应用。"
log_message "所有安装日志将记录在 ${LOG_FILE} 文件中。"

# --- 辅助函数：加载 NVM 环境变量 ---
# 确保 Node.js 命令在脚本的各个阶段都可用
load_nvm_environment() {
    log_message "尝试加载 NVM 环境变量..."
    export NVM_DIR="$HOME/.nvm"
    # 使用 || true 避免在NVM未安装时脚本退出，并确保文件存在才source
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" || true
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" || true

    # 尝试将 NVM 版本的 Node.js bin 路径添加到 PATH (如果 NVM 环境变量加载不足)
    if command -v nvm &> /dev/null && [ -n "$(nvm current 2>/dev/null)" ]; then
        local current_node_version=$(nvm current)
        local nvm_node_path="${NVM_DIR}/versions/node/${current_node_version}/bin"
        if [[ ":$PATH:" != *":$nvm_node_path:"* ]]; then
            export PATH="$nvm_node_path:$PATH"
            log_message "已将 NVM Node.js 路径 ${nvm_node_path} 添加到 PATH。"
        fi
    fi
}

# --- 辅助函数：生成随机密码 ---
generate_random_password() {
    head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 20 ; echo ''
}

# --- 辅助函数：计算 SHA256 哈希 (Node.js 兼容) ---
calculate_sha256_hash() {
    local password="$1"
    local salt="your_static_salt_for_image_bed" # 保持与 Node.js 后端中的 salt 一致
    
    # 再次检查 node 命令是否可用，如果不可用则退出
    if ! command -v node &> /dev/null
    then
        log_message "错误：'node' 命令在计算密码哈希时不可用。请确保 Node.js 已正确安装并通过NVM加载。尝试重新运行脚本。"
        exit 1
    fi
    node -e "const crypto = require('crypto'); console.log(crypto.createHash('sha256').update('$password' + '$salt').digest('hex'));"
}

# --- 收集用户信息 ---
echo ""
read -p "1. 请输入你的域名 (例如: example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    log_message "错误：域名不能为空。脚本退出。"
    exit 1
fi

read -p "2. 请输入允许上传图片的IP地址 (例如: 1.1.1.1): " ALLOWED_IP
if [ -z "$ALLOWED_IP" ]; then
    log_message "错误：允许的IP地址不能为空。脚本退出。"
    exit 1
fi

read -p "3. 请输入定期清理图片的月份间隔 (输入 0 或留空表示不清理，例如: 3 表示每3个月清理): " CLEANUP_MONTHS_INPUT
# 处理空输入和0，如果为空或0则设置为0，不清理
if [ -z "$CLEANUP_MONTHS_INPUT" ] || [ "$CLEANUP_MONTHS_INPUT" -eq 0 ] 2>/dev/null; then
    CLEANUP_MONTHS=0
    log_message "已选择不进行定期清理。"
else
    if ! [[ "$CLEANUP_MONTHS_INPUT" =~ ^[1-9][0-9]*$ ]]; then
        log_message "错误：清理月份间隔必须是正整数。脚本退出。"
        exit 1
    fi
    CLEANUP_MONTHS=$CLEANUP_MONTHS_INPUT
    log_message "将设置每 ${CLEANUP_MONTHS} 个月清理一次。"
fi

read -p "4. 请输入Certbot注册邮箱 (用于紧急续订通知): " CERTBOT_EMAIL
if [ -z "$CERTBOT_EMAIL" ]; then
    log_message "警告：Certbot邮箱未提供。建议提供以便接收续订通知。"
fi

# --- 密码设置 (注：ADMIN_RAW_PASSWORD会在这里被赋值，但ADMIN_PASSWORD_HASH会在Node.js安装后计算) ---
echo ""
read -p "5. 设置查看图片列表的密码 (留空则自动生成20位密码，最多100位): " ADMIN_RAW_PASSWORD
if [ -z "$ADMIN_RAW_PASSWORD" ]; then
    ADMIN_RAW_PASSWORD=$(generate_random_password)
    log_message "已自动生成密码：${ADMIN_RAW_PASSWORD}"
    log_message "请务必记录此密码，它是查看图片列表的唯一凭证！"
else
    if [ ${#ADMIN_RAW_PASSWORD} -gt 100 ]; then
        log_message "错误：密码长度不能超过100位。脚本退出。"
        exit 1
    fi
    log_message "已设置自定义密码。"
fi
echo ""

# --- 安装依赖 ---
install_dependencies() {
    log_message ">>> 正在更新系统并安装必要依赖 (curl, git, build-essential, nginx, certbot)..."
    apt update >> "$LOG_FILE" 2>&1 || { log_message "错误：apt update 失败。请检查网络连接或源配置。"; exit 1; }
    apt upgrade -y >> "$LOG_FILE" 2>&1 || { log_message "错误：apt upgrade 失败。"; exit 1; }
    apt install -y curl git build-essential nginx certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1 || { log_message "错误：安装依赖失败。"; exit 1; }
    log_message "依赖安装完成。"
}

# --- 安装 Node.js 和 npm (通过 NVM) ---
install_nodejs_nvm() {
    log_message ">>> 正在安装 NVM (Node Version Manager)..."
    # 防止 NVM 脚本将内容添加到当前shell的STDERR，导致脚本提前退出
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash >> "$LOG_FILE" 2>&1 || { log_message "错误：NVM下载或安装失败。"; exit 1; }
    
    # 加载 NVM 到当前 shell
    load_nvm_environment # 再次调用加载函数，确保在安装后环境立即生效

    log_message ">>> 正在安装 Node.js LTS 版本..."
    nvm install --lts >> "$LOG_FILE" 2>&1 || { log_message "错误：Node.js LTS安装失败。"; exit 1; }
    nvm use --lts >> "$LOG_FILE" 2>&1 || { log_message "错误：Node.js LTS使用失败。"; exit 1; }
    nvm alias default 'lts/*' >> "$LOG_FILE" 2>&1 || { log_message "错误：Node.js LTS别名设置失败。"; exit 1; }
    
    log_message "Node.js 和 npm 安装完成。版本: $(node -v), $(npm -v)"
}

# --- 设置项目目录和权限 ---
setup_directories_permissions() {
    log_message ">>> 正在创建项目目录 /var/www/image-bed/ 并设置权限..."
    mkdir -p /var/www/image-bed/backend >> "$LOG_FILE" 2>&1
    mkdir -p /var/www/image-bed/frontend >> "$LOG_FILE" 2>&1
    mkdir -p /var/www/image-bed/backend/uploads >> "$LOG_FILE" 2>&1
    
    # 将目录所有权设置为 www-data，因为 Nginx 通常以该用户运行，且 Node.js 进程也可能以此用户上下文运行
    chown -R www-data:www-data /var/www/image-bed >> "$LOG_FILE" 2>&1 || { log_message "错误：设置目录所有权失败。"; exit 1; }
    chmod -R 775 /var/www/image-bed >> "$LOG_FILE" 2>&1 || { log_message "错误：设置目录权限失败。"; exit 1; }
    log_message "目录创建和权限设置完成。"
}

# --- 部署后端代码 ---
deploy_backend_code() {
    log_message ">>> 正在生成后端代码 (index.js)..."
    # 使用 ENV 命令传递变量给 Node.js 进程，而不是直接写入文件
    cat <<EOF > /var/www/image-bed/backend/index.js
// index.js (Node.js Express 后端)

// 导入必要的模块
const express = require('express');
const multer = require('multer'); // 用于处理文件上传的中间件
const path = require('path'); // 用于处理文件路径
const fs = require('fs'); // 文件系统模块
const cors = require('cors'); // 允许跨域请求
const crypto = require('crypto'); // 用于密码哈希

const app = express();
const port = 3000; // 后端服务运行的端口

// --- 接收安装脚本设置的动态配置 (从环境变量读取) ---
const ALLOWED_IP = process.env.ALLOWED_IP; // 允许上传的 IP 地址
const ADMIN_PASSWORD_HASH = process.env.ADMIN_PASSWORD_HASH; // 管理密码的哈希值

if (!ALLOWED_IP || !ADMIN_PASSWORD_HASH) {
    console.error("错误：ALLOWED_IP 或 ADMIN_PASSWORD_HASH 未在环境变量中设置。请确保通过安装脚本启动后端。");
    process.exit(1); // 如果关键配置缺失，则退出进程
}
console.log("后端配置加载成功。");

// --- 密码哈希函数 ---
function hashPassword(password) {
    // 使用 SHA256 哈希密码，并添加盐值（这里使用一个固定值，生产环境应使用更安全的随机盐）
    const salt = 'your_static_salt_for_image_bed'; // 保持与安装脚本中的 salt 一致
    return crypto.createHash('sha256').update(password + salt).digest('hex');
}

// 配置 CORS，允许所有来源访问，实际部署时建议限制为你的前端域名
app.use(cors());
// 解析 JSON 请求体，用于密码验证
app.use(express.json());

// 定义图片上传目录
const uploadDir = path.join(__dirname, 'uploads');

// 检查上传目录是否存在，如果不存在则创建
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

// --- IP 白名单检查中间件 (应用于 /upload 接口) ---
app.use('/upload', (req, res, next) => {
    // 获取客户端 IP 地址
    // 注意：在 Nginx 反向代理下，真实的客户端 IP 通常在 X-Forwarded-For 头中
    const clientIp = req.headers['x-forwarded-for']?.split(',')[0].trim() || req.connection.remoteAddress;

    // 如果 IP 不在白名单内，则拒绝上传
    if (clientIp !== ALLOWED_IP) {
        console.warn(\`Unauthorized upload attempt from IP: \${clientIp}\`);
        return res.status(403).json({ message: \`对不起，您的 IP 地址 (\${clientIp}) 无权上传文件。\` });
    }
    next(); // 允许请求继续到下一个中间件 (multer)
});

// 配置 Multer 文件存储
const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, uploadDir); // 将文件存储到 uploads 目录
    },
    filename: function (req, file, cb) {
        // 设置文件名，使用原始文件名 + 时间戳，避免文件名冲突
        cb(null, file.fieldname + '-' + Date.now() + path.extname(file.originalname));
    }
});

// 创建 Multer 上传实例
const upload = multer({ storage: storage });

// 设置静态文件服务，用于直接通过 URL 访问上传的图片
app.use('/uploads', express.static(uploadDir));

// 定义图片上传 API 接口
app.post('/upload', upload.single('image'), (req, res) => {
    // 'image' 是前端表单中文件输入的 name 属性
    if (!req.file) {
        // 增加更详细的错误日志
        console.error('文件上传失败或未选择文件。请求体:', req.body);
        return res.status(400).json({ message: '未选择文件或文件上传失败。' });
    }

    // 获取上传文件的完整路径和文件名
    const imageUrl = \`/uploads/\${req.file.filename}\`;

    // 返回成功信息和图片 URL
    res.json({
        message: '图片上传成功！',
        imageUrl: imageUrl // 返回相对路径，Nginx 将会处理它
    });
});

// --- 新增功能：获取图片列表 API (密码保护) ---
app.post('/api/list-images', (req, res) => {
    const { password } = req.body;

    if (!password) {
        return res.status(400).json({ message: '请提供密码。' });
    }

    // 验证密码
    if (hashPassword(password) !== ADMIN_PASSWORD_HASH) {
        console.warn('Unauthorized access attempt to image list from IP:', req.headers['x-forwarded-for']?.split(',')[0].trim() || req.connection.remoteAddress);
        return res.status(401).json({ message: '密码不正确。' });
    }

    // 如果密码正确，读取 uploads 目录下的文件
    fs.readdir(uploadDir, (err, files) => {
        if (err) {
            console.error('读取图片目录失败:', err);
            return res.status(500).json({ message: '无法获取图片列表。' });
        }

        // 过滤掉非图片文件（根据常见图片扩展名）
        const imageFiles = files.filter(file => {
            const ext = path.extname(file).toLowerCase();
            return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg'].includes(ext);
        });

        // 返回图片文件名列表
        res.json({
            message: '图片列表获取成功！',
            images: imageFiles
        });
    });
});

// 简单的根路径响应，用于测试
app.get('/', (req, res) => {
    res.send('图床后端服务运行中！');
});

// 启动服务器
app.listen(port, () => {
    console.log(\`图床后端服务在 http://localhost:\${port} 端口启动\`);
    console.log(\`上传目录: \${uploadDir}\`);
});
EOF
    log_message "后端代码 index.js 已生成。"

    log_message ">>> 正在安装后端依赖 (express, multer, cors)..."
    cd /var/www/image-bed/backend >> "$LOG_FILE" 2>&1
    npm init -y >> "$LOG_FILE" 2>&1 || { log_message "错误：后端 npm init 失败。"; exit 1; }
    npm install express multer cors >> "$LOG_FILE" 2>&1 || { log_message "错误：后端依赖安装失败。"; exit 1; }
    log_message "后端依赖安装完成。"
}

# --- 部署前端代码 ---
deploy_frontend_code() {
    log_message ">>> 正在生成前端代码 (index.html, style.css, script.js)..."
    cat <<EOF > /var/www/image-bed/frontend/index.html
<!-- index.html -->
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>我的简易图床</title>
    <!-- 引入 Tailwind CSS CDN -->
    <script src="https://cdn.tailwindcss.com"></script>
    <!-- 引入自定义 CSS -->
    <link rel="stylesheet" href="style.css">
    <!-- 引入 Inter 字体 -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        body {
            font-family: 'Inter', sans-serif;
            overflow-x: hidden; /* 防止水平滚动 */
        }
    </style>
</head>
<body class="bg-gradient-to-r from-purple-400 via-pink-500 to-red-500 min-h-screen flex items-center justify-center p-4">

    <!-- 主上传界面 -->
    <div id="uploadView" class="bg-white p-8 rounded-xl shadow-2xl w-full max-w-md transform transition-all duration-500 hover:scale-105">
        <h1 class="text-3xl font-bold text-center text-gray-800 mb-6">上传你的图片</h1>

        <div class="mb-6">
            <label for="imageUpload" class="block text-gray-700 text-sm font-medium mb-2">选择图片文件:</label>
            <input type="file" id="imageUpload" accept="image/*" class="block w-full text-sm text-gray-900 border border-gray-300 rounded-lg cursor-pointer bg-gray-50 focus:outline-none file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100">
        </div>

        <button id="uploadButton" class="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg shadow-lg transform transition-transform duration-200 hover:scale-100 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-opacity-75">
            上传图片
        </button>

        <div id="messageBox" class="mt-6 p-4 rounded-lg text-sm text-center hidden"></div>

        <div id="imageLinkContainer" class="mt-6 hidden">
            <label class="block text-gray-700 text-sm font-medium mb-2">图片链接:</label>
            <div class="flex items-center space-x-2">
                <input type="text" id="imageLink" readonly class="flex-grow p-3 border border-gray-300 rounded-lg bg-gray-100 text-gray-800 focus:outline-none focus:border-blue-500">
                <button id="copyButton" class="bg-green-600 hover:bg-green-700 text-white font-bold py-2 px-4 rounded-lg shadow-md transform transition-transform duration-200 hover:scale-100 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-opacity-75">
                    复制
                </button>
            </div>
            <img id="uploadedImagePreview" src="" alt="上传图片预览" class="mt-4 max-w-full h-auto rounded-lg shadow-lg border border-gray-200 hidden">
        </div>

        <button id="showImagesButton" class="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-3 px-4 rounded-lg shadow-lg transform transition-transform duration-200 hover:scale-100 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-opacity-75 mt-4">
            查看已上传图片
        </button>
    </div>

    <!-- 图片列表界面 (初始隐藏) -->
    <div id="galleryView" class="bg-white p-8 rounded-xl shadow-2xl w-full max-w-3xl transform transition-all duration-500 hidden">
        <h1 class="text-3xl font-bold text-center text-gray-800 mb-6">已上传图片列表</h1>
        
        <!-- 密码输入框 -->
        <div id="passwordPrompt" class="mb-6">
            <label for="adminPassword" class="block text-gray-700 text-sm font-medium mb-2">请输入密码查看图片:</label>
            <input type="password" id="adminPassword" class="w-full p-3 border border-gray-300 rounded-lg bg-gray-100 text-gray-800 focus:outline-none focus:border-indigo-500" placeholder="管理员密码">
            <button id="submitPasswordButton" class="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg shadow-lg transform transition-transform duration-200 hover:scale-100 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-opacity-75 mt-3">
                提交
            </button>
            <div id="passwordMessage" class="mt-3 p-3 rounded-lg text-sm text-center hidden"></div>
        </div>

        <!-- 图片列表容器 -->
        <div id="imageGallery" class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4 hidden">
            <!-- 图片将在这里动态加载 -->
        </div>

        <button id="backToUploadButton" class="w-full bg-gray-500 hover:bg-gray-600 text-white font-bold py-3 px-4 rounded-lg shadow-lg transform transition-transform duration-200 hover:scale-100 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-opacity-75 mt-6">
            返回上传界面
        </button>
    </div>

    <!-- 引入自定义 JavaScript -->
    <script src="script.js"></script>
</body>
</html>
EOF
    log_message "前端 index.html 已生成。"

    cat <<EOF > /var/www/image-bed/frontend/style.css
/* style.css */
/* 自定义 Tailwind 样式覆盖和补充 */

/* 隐藏文件输入框的默认外观 */
input[type="file"]::-webkit-file-upload-button {
    cursor: pointer;
}

input[type="file"]::file-selector-button {
    cursor: pointer;
}

/* 消息框的默认样式 */
#messageBox.success {
    background-color: #d4edda;
    color: #155724;
    border: 1px solid #c3e6cb;
}

#messageBox.error {
    background-color: #f8d7da;
    color: #721c24;
    border: 1px solid #f5c6cb;
}

/* 密码消息框的样式 */
#passwordMessage.success {
    background-color: #d4edda;
    color: #155724;
    border: 1px solid #c3e6cb;
}

#passwordMessage.error {
    background-color: #f8d7da;
    color: #721c24;
    border: 1px solid #f5c6cb;
}

/* 图片缩略图的样式 */
.image-thumbnail {
    width: 100%;
    padding-top: 100%; /* 1:1 Aspect Ratio (creates a square) */
    position: relative;
    border-radius: 0.5rem; /* rounded-lg */
    overflow: hidden; /* ensure content doesn't spill */
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06); /* shadow-md */
    transition: transform 0.2s ease-in-out;
}

.image-thumbnail:hover {
    transform: scale(1.05);
}

.image-thumbnail img {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    object-fit: cover; /* Cover the area, cropping if necessary */
    cursor: pointer;
}
EOF
    log_message "前端 style.css 已生成。"

    cat <<EOF > /var/www/image-bed/frontend/script.js
// script.js
document.addEventListener('DOMContentLoaded', () => {
    // --- 界面元素引用 ---
    const uploadView = document.getElementById('uploadView');
    const galleryView = document.getElementById('galleryView');
    const imageUpload = document.getElementById('imageUpload');
    const uploadButton = document.getElementById('uploadButton');
    const messageBox = document.getElementById('messageBox');
    const imageLinkContainer = document.getElementById('imageLinkContainer');
    const imageLink = document.getElementById('imageLink');
    const copyButton = document.getElementById('copyButton');
    const uploadedImagePreview = document.getElementById('uploadedImagePreview');
    const showImagesButton = document.getElementById('showImagesButton');
    const backToUploadButton = document.getElementById('backToUploadButton');
    const adminPasswordInput = document.getElementById('adminPassword');
    const submitPasswordButton = document.getElementById('submitPasswordButton');
    const passwordPrompt = document.getElementById('passwordPrompt');
    const passwordMessage = document.getElementById('passwordMessage');
    const imageGallery = document.getElementById('imageGallery');

    // --- 后端 URL (由安装脚本动态设置) ---
    // 确保这里是你的实际域名，例如 'https://acus.rcghjcdn.top'
    const backendUrl = 'https://${DOMAIN}'; 

    // --- 消息显示函数 ---
    function showMessage(messageElement, message, type) {
        messageElement.textContent = message;
        messageElement.className = \`mt-6 p-4 rounded-lg text-sm text-center \${type}\`; 
        messageElement.classList.remove('hidden');

        if (type === 'success' || type === 'info') {
            setTimeout(() => {
                messageElement.classList.add('hidden');
            }, 5000);
        }
    }

    // --- 视图切换函数 ---
    function showUploadView() {
        uploadView.classList.remove('hidden');
        galleryView.classList.add('hidden');
        // 清理图片列表和密码输入框
        imageGallery.innerHTML = '';
        adminPasswordInput.value = '';
        passwordPrompt.classList.remove('hidden'); // 显示密码输入框
        imageGallery.classList.add('hidden'); // 隐藏图片列表
        showMessage(passwordMessage, '', 'hidden'); // 隐藏密码消息
    }

    function showGalleryView() {
        uploadView.classList.add('hidden');
        galleryView.classList.remove('hidden');
    }

    // --- 事件监听器 ---

    // 上传按钮点击事件
    uploadButton.addEventListener('click', async () => {
        const file = imageUpload.files[0];
        if (!file) {
            showMessage(messageBox, '请先选择一个图片文件！', 'error');
            return;
        }

        showMessage(messageBox, '正在上传...', 'info');
        uploadButton.disabled = true;
        imageLinkContainer.classList.add('hidden');
        uploadedImagePreview.classList.add('hidden');

        const formData = new FormData();
        formData.append('image', file);

        try {
            const response = await fetch(\`\${backendUrl}/upload\`, {
                method: 'POST',
                body: formData
            });

            const data = await response.json();

            if (response.ok) {
                showMessage(messageBox, data.message, 'success');
                const fullImageUrl = \`\${backendUrl}\${data.imageUrl}\`;
                
                imageLink.value = fullImageUrl;
                uploadedImagePreview.src = fullImageUrl;
                imageLinkContainer.classList.remove('hidden');
                uploadedImagePreview.classList.remove('hidden');
            } else {
                // 后端返回的错误信息
                showMessage(messageBox, \`上传失败: \${data.message || '未知错误'}\`, 'error');
            }
        } catch (error) {
            console.error('上传图片时发生错误:', error);
            showMessage(messageBox, '上传图片时发生网络错误，请稍后再试。', 'error');
        } finally {
            uploadButton.disabled = false;
        }
    });

    // 复制按钮点击事件
    copyButton.addEventListener('click', () => {
        imageLink.select();
        document.execCommand('copy'); 
        showMessage(messageBox, '图片链接已复制到剪贴板！', 'success');
    });

    // 显示图片列表按钮点击事件
    showImagesButton.addEventListener('click', () => {
        showGalleryView();
        adminPasswordInput.focus(); // 自动聚焦密码输入框
    });

    // 返回上传界面按钮点击事件
    backToUploadButton.addEventListener('click', () => {
        showUploadView();
    });

    // 提交密码按钮点击事件
    submitPasswordButton.addEventListener('click', async () => {
        const password = adminPasswordInput.value;
        if (!password) {
            showMessage(passwordMessage, '请输入密码。', 'error');
            return;
        }

        showMessage(passwordMessage, '正在验证密码...', 'info');
        submitPasswordButton.disabled = true;

        try {
            const response = await fetch(\`\${backendUrl}/api/list-images\`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ password: password })
            });

            const data = await response.json();

            if (response.ok) {
                showMessage(passwordMessage, data.message, 'success');
                passwordPrompt.classList.add('hidden'); // 隐藏密码输入框
                imageGallery.classList.remove('hidden'); // 显示图片列表容器
                renderImageGallery(data.images); // 渲染图片列表
            } else {
                showMessage(passwordMessage, \`密码验证失败: \${data.message || '未知错误'}\`, 'error');
            }
        } catch (error) {
            console.error('获取图片列表时发生错误:', error);
            showMessage(passwordMessage, '获取图片列表时发生网络错误，请稍后再试。', 'error');
        } finally {
            submitPasswordButton.disabled = false;
        }
    });

    // --- 渲染图片列表函数 ---
    function renderImageGallery(imageNames) {
        imageGallery.innerHTML = ''; // 清空现有列表
        if (imageNames.length === 0) {
            imageGallery.innerHTML = '<p class="text-center text-gray-600">目前没有已上传的图片。</p>';
            return;
        }

        imageNames.forEach(imageName => {
            const fullImageUrl = \`\${backendUrl}/uploads/\${imageName}\`;
            
            const imageDiv = document.createElement('div');
            imageDiv.className = 'image-thumbnail'; // 应用正方形样式

            const img = document.createElement('img');
            img.src = fullImageUrl;
            img.alt = imageName;
            img.loading = 'lazy'; // 延迟加载图片

            // 点击图片可以放大或在新标签页打开
            img.addEventListener('click', () => {
                window.open(fullImageUrl, '_blank');
            });

            imageDiv.appendChild(img);
            imageGallery.appendChild(imageDiv);
        });
    }

    // 初始化显示上传界面
    showUploadView();
});
EOF
    log_message "前端 script.js 已生成。"
    log_message "前端代码部署完成。"
}

# --- 配置 Nginx ---
configure_nginx() {
    log_message ">>> 正在配置 Nginx (初始 HTTP 配置)..."
    cat <<EOF > /etc/nginx/sites-available/image-bed.conf
# /etc/nginx/sites-available/image-bed.conf

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    client_max_body_size 20M; # 允许最大20MB的请求体

    root /var/www/image-bed/frontend;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /uploads/ {
        alias /var/www/image-bed/backend/uploads/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location /upload {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # 新增的图片列表 API 接口代理
    location /api/list-images {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # 允许较大的 JSON 请求体（例如传递长密码）
        client_max_body_size 1M; 
    }
}
EOF
    log_message "Nginx 配置文件 image-bed.conf 已生成。"

    # 创建软链接并移除默认配置
    ln -sf /etc/nginx/sites-available/image-bed.conf /etc/nginx/sites-enabled/ >> "$LOG_FILE" 2>&1 || { log_message "错误：创建 Nginx 软链接失败。"; exit 1; }
    rm -f /etc/nginx/sites-enabled/default >> "$LOG_FILE" 2>&1 # 使用-f强制删除，避免文件不存在报错
    
    log_message "测试 Nginx 配置..."
    nginx -t >> "$LOG_FILE" 2>&1 || { log_message "错误：Nginx 配置测试失败。请检查 ${LOG_FILE} 或手动运行 'nginx -t' 调试。"; exit 1; }
    
    log_message "重启 Nginx 服务..."
    systemctl restart nginx >> "$LOG_FILE" 2>&1 || { log_message "错误：Nginx 重启失败。请检查 'systemctl status nginx.service'。"; exit 1; }
    log_message "Nginx 初始配置完成并已重启。"
}

# --- 运行 Certbot 获取 SSL 证书 ---
run_certbot() {
    if [ -z "$CERTBOT_EMAIL" ]; then
        log_message "警告：未提供 Certbot 邮箱，Certbot 将在没有邮箱的情况下尝试获取证书。"
        log_message "这可能导致未来证书续订问题。建议重新运行脚本并提供邮箱。"
        certbot_cmd="certbot --nginx -d \"${DOMAIN}\" --agree-tos --redirect --no-eff-email"
    else
        certbot_cmd="certbot --nginx -d \"${DOMAIN}\" --agree-tos --redirect -m \"${CERTBOT_EMAIL}\" --no-eff-email"
    fi

    log_message ">>> 正在获取 Let's Encrypt SSL 证书 (Certbot)..."
    eval "$certbot_cmd" >> "$LOG_FILE" 2>&1 || { log_message "错误：Certbot 获取证书失败。请检查域名解析是否正确，或查看 /var/log/letsencrypt/letsencrypt.log 以获取更多详情。"; exit 1; }
    log_message "SSL 证书获取和配置完成。HTTPS 已启用！"
    log_message "Certbot 已自动修改 Nginx 配置，添加了 HTTPS 块并重启了 Nginx。"
}

# --- 设置 PM2 运行 Node.js 应用 ---
setup_pm2() {
    log_message ">>> 正在安装 PM2 (Node.js 进程管理器)..."
    npm install pm2 -g >> "$LOG_FILE" 2>&1 || { log_message "错误：PM2 安装失败。"; exit 1; }
    
    log_message ">>> 正在启动 Node.js 后端应用 (PM2)..."
    # 使用 env 命令在启动时设置环境变量，传递敏感信息给 Node.js 进程
    (cd /var/www/image-bed/backend && env ALLOWED_IP="${ALLOWED_IP}" ADMIN_PASSWORD_HASH="${ADMIN_PASSWORD_HASH}" pm2 start index.js --name "image-bed-backend") >> "$LOG_FILE" 2>&1 || { log_message "错误：PM2 启动应用失败。"; exit 1; }
    
    log_message "正在设置 PM2 开机自启..."
    pm2 startup systemd >> "$LOG_FILE" 2>&1 || { log_message "错误：PM2 systemd startup 设置失败。"; exit 1; }
    pm2 save >> "$LOG_FILE" 2>&1 || { log_message "错误：PM2 save 失败。"; exit 1; }
    log_message "PM2 配置完成。"
}

# --- 设置定期清理 Cron 任务 ---
setup_cleanup_cron() {
    log_message ">>> 正在部署清理脚本和设置 Cron 任务..."
    
    if [ "$CLEANUP_MONTHS" -eq 0 ]; then
        log_message "未设置定期清理，跳过 Cron 任务配置。"
        # 如果之前有任务，尝试删除，确保不留下旧的 Cron 任务
        (crontab -l 2>/dev/null | grep -v 'cleanup_uploads.js') | crontab - 2>/dev/null || true
        return # 退出函数
    fi

    # 计算 cleanUpAfterMs (毫秒)
    local CLEANUP_AFTER_MS=$((CLEANUP_MONTHS * 30 * 24 * 60 * 60 * 1000))

    cat <<EOF > /var/www/image-bed/backend/cleanup_uploads.js
// cleanup_uploads.js
const fs = require('fs');
const path = require('path');

const uploadDir = path.join(__dirname, 'uploads');
const cleanUpAfterMs = ${CLEANUP_AFTER_MS}; // 由安装脚本动态设置的清理时间 (毫秒)

console.log(\`清理脚本启动。检查目录: \${uploadDir}\`);
console.log(\`将删除创建时间早于 \${(new Date(Date.now() - cleanUpAfterMs)).toLocaleString()} 的文件。\`);

fs.readdir(uploadDir, (err, files) => {
    if (err) {
        console.error('无法读取上传目录:', err);
        return;
    }

    files.forEach(file => {
        const filePath = path.join(uploadDir, file);

        fs.stat(filePath, (err, stats) => {
            if (err) {
                console.error(\`无法获取文件状态 \${filePath}: \`, err);
                return;
            }

            if (stats.isFile() && (Date.now() - stats.birthtimeMs > cleanUpAfterMs)) {
                fs.unlink(filePath, (err) => {
                    if (err) {
                        console.error(\`删除文件失败 \${filePath}: \`, err);
                    } else {
                        console.log(\`已删除过期文件: \${filePath}\`);
                    }
                });
            }
        });
    });
    console.log('清理脚本执行完毕。');
});
EOF
    log_message "清理脚本 cleanup_uploads.js 已生成。"

    # 获取 Node.js 路径，确保使用完整的路径
    NODE_PATH=$(which node)
    if [ -z "$NODE_PATH" ]; then
        log_message "错误：无法找到 Node.js 可执行文件路径。请确保 Node.js 已正确安装。"
        exit 1
    fi

    # 添加 Cron 任务，先删除旧的清理任务行，再添加新的
    (crontab -l 2>/dev/null | grep -v 'cleanup_uploads.js' ; echo "0 0 1 */${CLEANUP_MONTHS} * ${NODE_PATH} /var/www/image-bed/backend/cleanup_uploads.js >> /var/log/image-bed-cleanup.log 2>&1") | crontab - >> "$LOG_FILE" 2>&1 || { log_message "错误：Cron 任务设置失败。"; exit 1; }
    log_message "Cron 定时清理任务已设置：每 ${CLEANUP_MONTHS} 个月清理一次。"
    log_message "你可以通过 'sudo crontab -l' 命令查看已设置的 Cron 任务。"
}

# --- 主安装流程 ---
log_message "开始执行安装流程..."

# --- 核心流程调整：先安装 Node.js，再计算哈希和其他部署步骤 ---
# 用户输入收集 -> (此处的ADMIN_RAW_PASSWORD已赋值)
# 依赖安装 (apt)
install_dependencies

# NVM 和 Node.js 安装
install_nodejs_nvm

# 此时Node.js已安装并加载，可以安全地计算密码哈希
ADMIN_PASSWORD_HASH=$(calculate_sha256_hash "$ADMIN_RAW_PASSWORD")
log_message "密码哈希已计算。"

# 继续其他部署步骤
setup_directories_permissions
deploy_backend_code # 后端代码依赖 ADMIN_PASSWORD_HASH
deploy_frontend_code
configure_nginx
run_certbot
setup_pm2       # PM2 启动时传递 ALLOWED_IP 和 ADMIN_PASSWORD_HASH
setup_cleanup_cron

log_message "--- 图床一键安装脚本执行完毕 ---"
log_message "恭喜！你的图床应该已经部署在 https://${DOMAIN} 上。"
log_message "请访问该 URL 进行测试。"
log_message "请务必牢记你的图片列表访问密码：${ADMIN_RAW_PASSWORD}" # 再次提醒密码
log_message "清理脚本的日志位于 /var/log/image-bed-cleanup.log"
log_message "安装脚本的完整日志位于 ${LOG_FILE}"
log_message "如果你遇到任何问题，请检查这些日志文件。"

exit 0
