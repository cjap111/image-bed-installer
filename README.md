# image-bed-installer
A one-click installation script for an HTTPS image hosting service on Ubuntu VPS.
一键脚本
 `curl -sL https://raw.githubusercontent.com/cjap111/image-bed-installer/main/install_image_bed.sh -o /tmp/install_image_bed.sh && sudo chmod +x /tmp/install_image_bed.sh && sudo /tmp/install_image_bed.sh`
 
Image Bed Installer (图床一键安装脚本)
Secure, Controllable, and Automated Image Hosting Solution on Ubuntu VPS
安全、可控、自动化维护的 Ubuntu VPS 图床解决方案
Introduction / 项目简介
This project provides a one-click installation script to deploy a personal image hosting service (image bed) on an Ubuntu Virtual Private Server (VPS). It is designed for individuals who seek a secure, controllable, and low-maintenance solution for storing and sharing images.

本项目提供一个一键安装脚本，用于在 Ubuntu 虚拟私人服务器 (VPS) 上部署个人图片托管服务（图床）。本方案旨在为用户提供一个安全、可控且易于维护的图片存储与分享解决方案。

Key Features / 方案特点
HTTPS Encryption: Ensures secure access and image transfer with full HTTPS encryption via Nginx and Let's Encrypt certificates.
HTTPS 全程加密： 通过 Nginx 和 Let's Encrypt 证书，确保图床访问和图片传输的安全性。

IP-Restricted Uploads: The backend supports IP whitelisting, allowing only specified IP addresses to upload images, effectively preventing unauthorized usage.
IP 上传限制： 后端支持配置 IP 白名单，只允许特定 IP 地址上传图片，有效防止滥用。

Password-Protected Image Gallery: A separate image gallery interface requiring a correct password to view uploaded image thumbnails. The gallery features a responsive square grid layout for easy browsing.
密码保护的图片列表： 提供一个独立的图片列表界面，需输入正确密码才能查看已上传的图片缩略图。列表展示采用自适应正方形布局，方便浏览。

Automated Cleanup: Configurable scheduled tasks automatically delete old images after a specified number of months, helping to manage storage space.
定期自动清理： 可配置定时任务，自动删除指定月份前的旧图片，释放存储空间。

One-Click Deployment Script: A comprehensive Shell script automates the entire deployment process, from environment setup to application configuration.
一键部署脚本： 一个全面的 Shell 脚本自动化了从环境配置到应用部署的全部过程。

Technology Stack / 技术栈
Backend: Node.js + Express.js
后端： Node.js + Express.js

Web Server / Reverse Proxy: Nginx
Web 服务器 / 反向代理： Nginx

SSL Certificates: Let's Encrypt (managed by Certbot)
SSL 证书： Let's Encrypt (通过 Certbot 自动管理)

Process Manager: PM2
进程管理： PM2

Scheduled Tasks: Cron
定时任务： Cron

How to Deploy / 部署指南
Deployment is straightforward. You will need an Ubuntu VPS and a domain name pointing to your VPS's public IP address. Execute the following one-liner command on your VPS, and the script will guide you through the configuration.

部署过程非常简单。你需要一台 Ubuntu 系统的 VPS 和一个解析到 VPS 公网 IP 的域名。在 VPS 上执行以下一键命令，脚本将引导你完成配置。

curl -sL https://raw.githubusercontent.com/cjap111/image-bed-installer/main/install_image_bed.sh -o /tmp/install_image_bed.sh && sudo chmod +x /tmp/install_image_bed.sh && sudo /tmp/install_image_bed.sh

Important Notes during Deployment (部署时的重要提示):

Ensure your domain name is correctly resolved to your VPS's public IP before running the script.
请确保在运行脚本前，你的域名已经正确解析到 VPS 的公网 IP。

The script will prompt you for essential information (domain, allowed upload IP, cleanup interval, Certbot email, and gallery password). Please input carefully.
脚本运行过程中会提示你输入关键信息（域名、允许上传的 IP、清理间隔、Certbot 邮箱和图片列表密码），请仔细核对。

Crucially, remember or securely store the generated/set password for the image gallery. It is your credential to view the uploaded images list.
至关重要：请务必记住或安全存储图片列表的访问密码。它是你查看已上传图片列表的唯一凭证。

Important Disclaimer and Legal Notice / 重要免责声明与法律提示
By using this script and deploying the image hosting service, you, the user, acknowledge and agree to the following:

通过使用本脚本并部署图片托管服务，您，作为使用者，即表示您理解并同意以下声明：

Project Purpose: This project is provided for educational purposes, personal use, and as a demonstration of self-hosted solutions. It is designed to offer a basic, secure, and manageable image hosting service.
项目目的： 本项目仅为教育目的、个人使用以及作为自托管解决方案的演示而提供。其设计旨在提供一个基本的、安全且易于管理的图片托管服务。

No Warranty: The project is provided "as is" without any warranty, express or implied. The developer makes no guarantees regarding its functionality, security, reliability, or suitability for any particular purpose.
无担保： 本项目按“原样”提供，不附带任何明示或暗示的担保。开发者不就其功能性、安全性、可靠性或适用于任何特定目的作出任何保证。

User Responsibility (使用者责任):

Legal Compliance (法律合规性): You are solely responsible for ensuring that your use of this image hosting service complies with all applicable local, national, and international laws and regulations. This includes, but is not limited to, laws regarding content hosting, data privacy, copyright, intellectual property, and content restrictions in your jurisdiction and the jurisdiction where your VPS is located.
法律合规性： 您全权负责确保您使用本图片托管服务遵守所有适用的地方、国家和国际法律法规。这包括但不限于与您所在地及您的 VPS 所在地的内容托管、数据隐私、版权、知识产权和内容限制相关的法律。

Content Liability (内容责任): You are solely responsible for all content uploaded, stored, and distributed through your deployed image bed. The developer of this script has no control over, and assumes no responsibility for, the content that users choose to upload.
内容责任： 您全权负责通过您部署的图床上传、存储和分发的所有内容。本脚本的开发者对用户选择上传的内容不具有控制权，也不承担任何责任。

Misuse (滥用): The developer explicitly disclaims any responsibility for any misuse of this script or the resulting image hosting service, including but not limited to, hosting illegal, offensive, or infringing content.
滥用： 开发者明确声明，对本脚本或由此产生的图片托管服务的任何滥用行为（包括但不限于托管非法、冒犯性或侵权内容）不承担任何责任。

Security Measures: While the script incorporates basic security measures (HTTPS, IP restriction, password protection), no system is entirely foolproof. You are encouraged to implement additional security best practices for your VPS.
安全措施： 尽管本脚本包含了基本的安全措施（HTTPS、IP 限制、密码保护），但没有任何系统是万无一失的。建议您为您的 VPS 实施额外的安全最佳实践。

Data Loss (数据丢失): The developer is not responsible for any data loss that may occur. You are advised to implement your own backup strategies for your hosted images.
数据丢失： 开发者不承担任何可能发生的数据丢失责任。建议您自行实施托管图片的备份策略。

Support and Contribution / 支持与贡献
For questions, bug reports, or feature requests, please open an issue on the GitHub repository. Contributions are welcome!

如有疑问、Bug 报告或功能请求，请在 GitHub 仓库中提交 Issue。欢迎贡献代码！

License / 许可证
This project is licensed under the MIT License. See the LICENSE file for details.

本项目根据 MIT 许可证授权。详情请参见 LICENSE 文件。
