export default function ErrorBanner({ message }) {
  if (!message) return null;
  return <div className="error-banner">Something went wrong: {message}</div>;
}
