#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 安装必要的依赖
function install_dependencies() {
    apt update && apt upgrade -y
    apt install curl wget jq make gcc nano -y
}

# 安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装，版本: $(node -v)"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装，版本: $(npm -v)"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装，版本: $(pm2 -v)"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

# 安装Story节点
function install_story_node() {
    install_dependencies
    install_nodejs_and_npm
    install_pm2  # 确保 PM2 已安装

    echo "开始安装Story节点..."

    # 下载执行客户端和共识客户端
    echo "下载执行客户端和共识客户端..."
    wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
    wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.11-2a25df1.tar.gz

    # 解压下载的文件
    tar -xzf geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
    tar -xzf story-linux-amd64-0.9.11-2a25df1.tar.gz

    echo "默认数据文件夹设置为:"
    echo "Story数据根: ${STORY_DATA_ROOT}"
    echo "Geth数据根: ${GETH_DATA_ROOT}"

    # 执行客户端设置
    echo "设置执行客户端..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sudo xattr -rd com.apple.quarantine ./geth
    fi

    # 使用pm2运行执行客户端
    cp /root/geth-linux-amd64-0.9.2-ea9f0d2/geth /usr/local/bin
    pm2 start /usr/local/bin/geth --name story-geth -- --iliad --syncmode full

    # 共识客户端设置
    echo "设置共识客户端..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sudo xattr -rd com.apple.quarantine ./story
    fi

    # 初始化共识客户端
    cp /root/story-linux-amd64-0.9.11-2a25df1/story /usr/local/bin
    /usr/local/bin/story init --network iliad

    # 使用pm2运行共识客户端
    pm2 start /usr/local/bin/story --name story-client -- run

    echo "Story节点安装完成！"
}

# 清除状态的函数
function clear_state() {
    echo "清除状态并重新初始化节点..."
    rm -rf ${GETH_DATA_ROOT} && pm2 start /usr/local/bin/geth --name story-geth -- --iliad --syncmode full
    rm -rf ${STORY_DATA_ROOT} && /usr/local/bin/story init --network iliad && pm2 start /usr/local/bin/story --name story-client -- run
}

# 检查节点状态的函数
function check_status() {
    echo "检查Geth状态..."
    pm2 logs story-geth
    pm2 logs story-client
}

# 检查 .env 文件并读取私钥
function check_env_file() {
    if [ -f ".env" ]; then
        # 读取 .env 文件中的 PRIVATE_KEY
        source .env
        echo "已加载 .env 文件，私钥为: ${PRIVATE_KEY}"
    else
        # 如果 .env 文件不存在，提示用户输入私钥
        read -p "请输入您的 ETH 钱包私钥（确保没有 0x 前缀）: " PRIVATE_KEY
        # 创建 .env 文件
        echo "# ~/story/.env" > .env
        echo "PRIVATE_KEY=${PRIVATE_KEY}" >> .env
        echo ".env 文件已创建，内容如下："
        cat .env
        echo "请确保该账户已获得IP资金（可参考教程领水页面获取资金）。"
    fi
}

# 设置验证器的函数
function setup_validator() {
    echo "设置验证器..."
    # 检查 .env 文件并读取私钥
    check_env_file

    # 提示用户进行验证器操作
    echo "您可以执行以下验证器操作："
    echo "1. 导出验证器密钥"
    echo "2. 创建新的验证器"
    echo "3. 质押到现有验证器"
    echo "4. 取消质押"
    echo "5. 代表其他委托者质押"
    echo "6. 代表其他委托者取消质押"
    echo "7. 添加操作员"
    echo "8. 移除操作员"
    echo "9. 设置提取地址"
    read -p "请输入选项（1-9）: " OPTION

    case $OPTION in
    1) export_validator_key ;;
    2) create_validator ;;
    3) stake_to_validator ;;
    4) unstake_from_validator ;;
    5) stake_on_behalf ;;
    6) unstake_on_behalf ;;
    7) add_operator ;;
    8) remove_operator ;;
    9) set_withdrawal_address ;;
    *) echo "无效选项。" ;;
    esac
}

# 导出验证器密钥
function export_validator_key() {
    echo "导出验证器密钥..."
    /usr/local/bin/story validator export
}

# 创建新的验证器
function create_validator() {
    read -p "请输入质押金额（以 wei 为单位）: " AMOUNT_TO_STAKE_IN_WEI
    /usr/local/bin/story validator create --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# 质押到现有验证器
function stake_to_validator() {
    read -p "请输入验证器公钥（Base64格式）: " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "请输入质押金额（以 wei 为单位）: " AMOUNT_TO_STAKE_IN_WEI
    /usr/local/bin/story validator stake --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# 取消质押
function unstake_from_validator() {
    read -p "请输入验证器公钥（Base64格式）: " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "请输入取消质押金额（以 wei 为单位）: " AMOUNT_TO_UNSTAKE_IN_WEI
    /usr/local/bin/story validator unstake --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --unstake ${AMOUNT_TO_UNSTAKE_IN_WEI}
}

# 代表其他委托者质押
function stake_on_behalf() {
    read -p "请输入委托者公钥（Base64格式）: " DELEGATOR_PUB_KEY_IN_BASE64
    read -p "请输入验证器公钥（Base64格式）: " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "请输入质押金额（以 wei 为单位）: " AMOUNT_TO_STAKE_IN_WEI
    /usr/local/bin/story validator stake-on-behalf --delegator-pubkey ${DELEGATOR_PUB_KEY_IN_BASE64} --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# 代表其他委托者取消质押
function unstake_on_behalf() {
    read -p "请输入委托者公钥（Base64格式）: " DELEGATOR_PUB_KEY_IN_BASE64
    read -p "请输入验证器公钥（Base64格式）: " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "请输入取消质押金额（以 wei 为单位）: " AMOUNT_TO_UNSTAKE_IN_WEI
    /usr/local/bin/story validator unstake-on-behalf --delegator-pubkey ${DELEGATOR_PUB_KEY_IN_BASE64} --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --unstake ${AMOUNT_TO_UNSTAKE_IN_WEI}
}

# 添加操作员
function add_operator() {
    read -p "请输入操作员的EVM地址: " OPERATOR_EVM_ADDRESS
    /usr/local/bin/story validator add-operator --operator ${OPERATOR_EVM_ADDRESS}
}

# 移除操作员
function remove_operator() {
    read -p "请输入操作员的EVM地址: " OPERATOR_EVM_ADDRESS
    /usr/local/bin/story validator remove-operator --operator ${OPERATOR_EVM_ADDRESS}
}

# 设置提取地址
function set_withdrawal_address() {
    read -p "请输入新的提取地址: " NEW_WITHDRAWAL_ADDRESS
    /usr/local/bin/story validator set-withdrawal-address --address ${NEW_WITHDRAWAL_ADDRESS}
}

# 主菜单
function main_menu() {
    clear
    echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
    echo "============================Artela节点安装===================================="
    echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
    echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
    echo "节点社区 Discord 社群:https://discord.gg/GbMV5EcNWF"
    echo "请选择要执行的操作:"
    echo "1. 安装Story节点"
    echo "2. 清除状态并重新初始化"
    echo "3. 检查节点状态"
    echo "4. 设置验证器"
    echo "5. 退出"
    read -p "请输入选项（1-5）: " OPTION

    case $OPTION in
    1) install_story_node ;;
    2) clear_state ;;
    3) check_status ;;
    4) setup_validator ;;
    5) exit 0 ;;
    *) echo "无效选项。" ;;
    esac
}

# 显示主菜单
check_env_file  # 在主菜单之前检查 .env 文件
main_menu
