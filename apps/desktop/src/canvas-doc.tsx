import React from "react";
import ReactDOM from "react-dom/client";
import { CanvasDocumentationPage } from "./CanvasDocumentationPage";
import "./styles.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <CanvasDocumentationPage />
  </React.StrictMode>
);
