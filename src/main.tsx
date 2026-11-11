import React from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './ui/App';
import './ui/app.css';

const root = document.getElementById('root');
if (!root) throw new Error('Не найден корневой элемент приложения CYDLE.');

createRoot(root).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
