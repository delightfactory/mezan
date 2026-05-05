const fs = require('fs');
const path = 'src/pages/gameya/GameyaPayout.tsx';
let content = fs.readFileSync(path, 'utf8');

// Update imports
content = content.replace(
  "import { ArrowRight, CheckCircle, AlertCircle, TrendingUp, DollarSign } from 'lucide-react';",
  "import { ArrowRight, CheckCircle, AlertCircle, TrendingUp, DollarSign } from 'lucide-react';\nimport { WalletSelect } from '../../components/WalletSelect';\nimport { getDefaultWalletId } from '../../utils/walletHelpers';"
);

// Update default wallet
content = content.replace(
  "setWalletId(fetchedWallets.find(w => w.type === 'REAL' && !w.is_archived)?.id || '');",
  "setWalletId(getDefaultWalletId(fetchedWallets, 'REAL'));"
);

// Update select
const selectRegex = /<select[\s\S]*?<\/select>/;
const walletSelectStr = `<WalletSelect
                wallets={wallets}
                value={walletId}
                onChange={setWalletId}
                required
                filter="REAL"
                className="block w-full rounded-xl border-gray-300 py-3 pl-3 pr-10 text-base focus:border-primary-500 focus:outline-none focus:ring-primary-500 sm:text-sm"
              />`;
content = content.replace(selectRegex, walletSelectStr);

fs.writeFileSync(path, content, 'utf8');
