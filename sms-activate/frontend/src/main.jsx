import React from 'react';
import ReactDOM from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import Login from './pages/Login.jsx';
import Dashboard from './pages/Dashboard.jsx';
import AdminCredits from './pages/AdminCredits.jsx';

const router = createBrowserRouter([
  { path: '/', element: <Login/> },
  { path: '/login', element: <Login/> },
  { path: '/dashboard', element: <Dashboard/> },
  { path: '/admin', element: <AdminCredits/> }
]);

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <RouterProvider router={router}/>
  </React.StrictMode>
);
