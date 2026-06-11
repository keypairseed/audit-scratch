#!/bin/bash
# setup.sh — запусти из ~/audit-scratch
# chmod +x setup.sh && ./setup.sh

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo "=== audit-scratch setup ==="

# ── 1. Проверка что мы в нужном месте ──────────────────────────
[ -d ".git" ] || err "Не в git репозитории. Сделай: cd ~/audit-scratch"
ok "Git репозиторий найден"

# ── 2. Git config (нужен для forge install) ────────────────────
if [ -z "$(git config --global user.email)" ]; then
    git config --global user.email "audit@local.dev"
    git config --global user.name "Auditor"
    ok "Git user настроен"
fi

# ── 3. Исправить foundry.toml — должен быть в корне, не в test/ ─
if [ -f "test/foundry.toml" ] && [ ! -f "foundry.toml" ]; then
    mv test/foundry.toml ./foundry.toml
    ok "foundry.toml перемещён в корень проекта"
elif [ -f "foundry.toml" ]; then
    ok "foundry.toml уже в корне"
fi

# ── 4. Создать все нужные директории ──────────────────────────
mkdir -p .github/workflows
mkdir -p src/interfaces
mkdir -p lib
ok "Директории созданы"

# ── 5. forge install (правильный синтаксис для v1.7.1) ─────────
if [ ! -d "lib/forge-std" ]; then
    echo "Устанавливаю forge-std..."
    # В Foundry 1.7.1 — без --no-commit, просто:
    forge install foundry-rs/forge-std
    ok "forge-std установлен"
else
    ok "forge-std уже установлен"
fi

# ── 6. Проверить RPC ───────────────────────────────────────────
echo "Проверяю бесплатный RPC..."
RESPONSE=$(curl -s -X POST https://eth.llamarpc.com \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
if echo "$RESPONSE" | grep -q '"result"'; then
    BLOCK=$(echo "$RESPONSE" | python3 -c "import sys,json; print(int(json.load(sys.stdin)['result'],16))")
    ok "LlamaRPC работает — текущий блок: $BLOCK"
    warn "Запиши этот URL: https://eth.llamarpc.com"
    warn "Для тяжёлых fork-тестов — зарегистрируйся на alchemy.com (бесплатно)"
else
    warn "LlamaRPC недоступен, пробую другой..."
    RESPONSE2=$(curl -s -X POST https://ethereum.publicnode.com \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
    if echo "$RESPONSE2" | grep -q '"result"'; then
        ok "publicnode.com работает"
    fi
fi

# ── 7. Создать .env шаблон ─────────────────────────────────────
if [ ! -f ".env" ]; then
    cat > .env << 'EOF'
# Локальные переменные (НЕ коммитить — есть в .gitignore)
# Скопируй в GitHub Secrets с теми же именами

ETH_RPC_URL=https://eth.llamarpc.com
ETHERSCAN_API_KEY=ЗАМЕНИ_НА_СВОЙ_КЛЮЧ
EOF
    ok ".env создан (заполни своими ключами)"
fi

# ── 8. .gitignore ──────────────────────────────────────────────
if [ ! -f ".gitignore" ]; then
    cat > .gitignore << 'EOF'
out/
cache/
.env
*.env
node_modules/
broadcast/
EOF
    ok ".gitignore создан"
fi

echo ""
echo "=== Готово! Следующие шаги: ==="
echo "1. Запуши на GitHub:  git add . && git commit -m 'setup' && git push"
echo "2. Добавь секреты в GitHub (Settings → Secrets):"
echo "   ETH_RPC_URL      = https://eth.llamarpc.com"
echo "   ETHERSCAN_API_KEY = [с etherscan.io/myapikey]"
echo "3. Проверь локально: forge build"
