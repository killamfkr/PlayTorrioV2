import { Router } from 'express';
import {
  authMiddleware,
  registerUser,
  loginUser,
  signToken,
  setAuthCookie,
  clearAuthCookie,
} from './auth.js';

const router = Router();

router.post('/register', (req, res) => {
  if (process.env.ALLOW_REGISTRATION === 'false') {
    return res.status(403).json({ error: 'Registration is disabled' });
  }
  try {
    const { username, password } = req.body;
    const user = registerUser(username, password);
    const token = signToken(user);
    setAuthCookie(res, token);
    res.json({ user: { id: user.id, username: user.username } });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

router.post('/login', (req, res) => {
  try {
    const { username, password } = req.body;
    const user = loginUser(username, password);
    const token = signToken(user);
    setAuthCookie(res, token);
    res.json({ user });
  } catch (err) {
    res.status(401).json({ error: err.message });
  }
});

router.post('/logout', (_req, res) => {
  clearAuthCookie(res);
  res.json({ ok: true });
});

router.get('/me', authMiddleware, (req, res) => {
  res.json({ user: req.user });
});

export default router;
