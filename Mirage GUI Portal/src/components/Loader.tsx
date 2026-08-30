import styles from './Loader.module.css';

interface LoaderProps {
  active: boolean;
  text?: string;
}

export function Loader({ active, text = "Orchestrating Deception Fabric..." }: LoaderProps) {
  if (!active) return null;

  return (
    <div className={styles.loaderContainer}>
      <div className={styles.alertingWrapper}>
        <svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg" className={styles.loaderSvg}>
          <defs>
            <linearGradient id="redGradLoader" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor="#ef4444" />
              <stop offset="100%" stopColor="#991b1b" />
            </linearGradient>
          </defs>
          <path d="M 45 20 L 55 20 L 95 100 L 79 100 L 50 42 L 21 100 L 5 100 Z" fill="url(#redGradLoader)" />
          <circle cx="50" cy="78" r="9" fill="#dc2626" />
        </svg>
      </div>
      <p className={styles.loaderText}>{text}</p>
    </div>
  );
}
