import React from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { AppShell } from './components/layout/AppShell';
import { Login } from './pages/Login';
import { Signup } from './pages/Signup';
import { Onboarding } from './pages/Onboarding';
import { Dashboard } from './pages/Dashboard';
import { Wallets } from './pages/Wallets';
import { AddIncome } from './pages/transactions/AddIncome';
import { AddExpense } from './pages/transactions/AddExpense';
import { Transfer } from './pages/transactions/Transfer';
import { DebtsList } from './pages/debts/DebtsList';
import { ReceiveLoan } from './pages/debts/ReceiveLoan';
import { DisburseLoan } from './pages/debts/DisburseLoan';
import { DebtDetails } from './pages/debts/DebtDetails';
import { DebtPayment } from './pages/debts/DebtPayment';
import { GameyaList } from './pages/gameya/GameyaList';
import { GameyaDetails } from './pages/gameya/GameyaDetails';
import { GameyaInstallmentPayment } from './pages/gameya/GameyaInstallmentPayment';
import { GameyaPayout } from './pages/gameya/GameyaPayout';
import { ChangeGameyaTurn } from './pages/gameya/ChangeGameyaTurn';
import { UpdateGameyaSchedule } from './pages/gameya/UpdateGameyaSchedule';
import { ExitGameya } from './pages/gameya/ExitGameya';
import { CreateGameyaWizard } from './pages/gameya/CreateGameyaWizard';
import { BudgetsList } from './pages/budgets/BudgetsList';
import { CreateBudget } from './pages/budgets/CreateBudget';
import { CommitmentsList } from './pages/commitments/CommitmentsList';
import { CreateCommitment } from './pages/commitments/CreateCommitment';
import { CommitmentDetails } from './pages/commitments/CommitmentDetails';
import { PayCommitment } from './pages/commitments/PayCommitment';
import { FamilySettings } from './pages/family/FamilySettings';
import { AccountSecurity } from './pages/auth/AccountSecurity';
import { ForgotPassword } from './pages/auth/ForgotPassword';
import { ResetPassword } from './pages/auth/ResetPassword';
import { AcceptInvitation } from './pages/auth/AcceptInvitation';
import { AccountSuspended } from './pages/auth/AccountSuspended';

import { SplashScreen } from './components/layout/SplashScreen';

import { CategoriesManagement } from './pages/categories/CategoriesManagement';

const ProtectedRoute = ({ children }: { children: React.ReactNode }) => {
  const { user, isLoading } = useAuth();

  if (isLoading) {
    return <SplashScreen />;
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
};

export const App: React.FC = () => {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/signup" element={<Signup />} />
          <Route path="/forgot-password" element={<ForgotPassword />} />
          <Route path="/reset-password" element={<ResetPassword />} />
          <Route path="/accept-invitation" element={<AcceptInvitation />} />
          <Route path="/account/suspended" element={<ProtectedRoute><AccountSuspended /></ProtectedRoute>} />

          <Route path="/" element={<ProtectedRoute><AppShell /></ProtectedRoute>}>
            <Route index element={<Navigate to="/dashboard" replace />} />
            <Route path="onboarding" element={<Onboarding />} />
            <Route path="dashboard" element={<Dashboard />} />
            <Route path="wallets" element={<Wallets />} />
            <Route path="categories" element={<CategoriesManagement />} />
            <Route path="transactions/income" element={<AddIncome />} />
            <Route path="transactions/expense" element={<AddExpense />} />
            <Route path="transactions/transfer" element={<Transfer />} />
            <Route path="debts" element={<DebtsList />} />
            <Route path="debts/receive-loan" element={<ReceiveLoan />} />
            <Route path="debts/disburse-loan" element={<DisburseLoan />} />
            <Route path="debts/:id" element={<DebtDetails />} />
            <Route path="debts/:id/payment" element={<DebtPayment />} />
            
            <Route path="gameya" element={<GameyaList />} />
            <Route path="gameya/new" element={<CreateGameyaWizard />} />
            <Route path="gameya/:id" element={<GameyaDetails />} />
            <Route path="gameya/:id/installments/:installmentId/pay" element={<GameyaInstallmentPayment />} />
            <Route path="gameya/:id/payout" element={<GameyaPayout />} />
            <Route path="gameya/:id/change-turn" element={<ChangeGameyaTurn />} />
            <Route path="gameya/:id/update-schedule" element={<UpdateGameyaSchedule />} />
            <Route path="gameya/:id/exit" element={<ExitGameya />} />

            <Route path="budgets" element={<BudgetsList />} />
            <Route path="budgets/new" element={<CreateBudget />} />

            <Route path="commitments" element={<CommitmentsList />} />
            <Route path="commitments/new" element={<CreateCommitment />} />
            <Route path="commitments/:id" element={<CommitmentDetails />} />
            <Route path="commitments/:commitmentId/occurrences/:occurrenceId/pay" element={<PayCommitment />} />

            <Route path="family/settings" element={<FamilySettings />} />
            <Route path="account/security" element={<AccountSecurity />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
};

export default App;
