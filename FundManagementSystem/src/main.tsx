import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

const preventNumberInputWheel = (event: WheelEvent) => {
  const target = event.target

  if (target instanceof HTMLInputElement && target.type === 'number') {
    target.blur()
  }
}

document.addEventListener('wheel', preventNumberInputWheel, { capture: true, passive: true })

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
