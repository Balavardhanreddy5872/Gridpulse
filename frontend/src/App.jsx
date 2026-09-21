import { BrowserRouter, Routes, Route } from "react-router-dom";
import Sidebar from "./components/Sidebar";
import Dashboard from "./pages/Dashboard";
import RegionalForecast from "./pages/RegionalForecast";
import Alerts from "./pages/Alerts";
import Documents from "./pages/Documents";
import AsyncJobs from "./pages/AsyncJobs";

export default function App() {
  return (
    <BrowserRouter>
      <div className="app-shell">
        <Sidebar />
        <main className="main">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/forecast" element={<RegionalForecast />} />
            <Route path="/alerts" element={<Alerts />} />
            <Route path="/documents" element={<Documents />} />
            <Route path="/jobs" element={<AsyncJobs />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}
