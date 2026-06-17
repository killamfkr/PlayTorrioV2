import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { createUser, getUserByUsername, getUserById } from './db.js';

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const SECRET_FILE = path.join(DATA_DIR, '.jwt_secret');

function getJwtSecret() {
  if (process.env.JWT_SECRET) return process.env.JWT_SECRET;
  if (fs.existsSync(SECRET_FILE)) return fs.readFileSync(SECRET_FILE, 'utf8').trim();
  const secret = crypto.randomBytes(48).toString('hex');
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(SECRET_FILE, secret, { mode: 0o600 });
  return secret;
}

const JWT_SECRET = getJwtSecret();
const TOKEN_MAX_AGE = 30 * 24 * 60 * 60; // 30 days

export function hashPassword(password) {
  return bcrypt.hashSync(password, 12);
}

export function verifyPassword(password, hash) {
  return bcrypt.compareSync(password, hash);
}

export function signToken(user) {
  return jwt.sign({ sub: user.id, username: user.username }, JWT_SECRET, {
    expiresIn: TOKEN_MAX_AGE,
  });
}

export function verifyToken(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch {
    return null;
  }
}

export function registerUser(username, password) {
  const trimmed = username?.trim();
  if (!trimmed || trimmed.length < 3) {
    throw new Error('Username must be at least 3 characters');
  }
  if (!password || password.length < 6) {
    throw new Error('Password must be at least 6 characters');
  }
  if (getUserByUsername(trimmed)) {
    throw new Error('Username already taken');
  }
  const passwordHash = hashPassword(password);
  return createUser(trimmed, passwordHash);
}

export function loginUser(username, password) {
  const user = getUserByUsername(username?.trim());
  if (!user || !verifyPassword(password, user.password_hash)) {
    throw new Error('Invalid username or password');
  }
  return { id: user.id, username: user.username };
}

export function authMiddleware(req, res, next) {
  const token = req.cookies?.token;
  if (!token) {
    return res.status(401).json({ error: 'Not authenticated' });
  }
  const payload = verifyToken(token);
  if (!payload) {
    return res.status(401).json({ error: 'Session expired' });
  }
  const user = getUserById(payload.sub);
  if (!user) {
    return res.status(401).json({ error: 'User not found' });
  }
  req.user = user;
  next();
}

export function optionalAuth(req, _res, next) {
  const token = req.cookies?.token;
  if (token) {
    const payload = verifyToken(token);
    if (payload) {
      const user = getUserById(payload.sub);
      if (user) req.user = user;
    }
  }
  next();
}

export function setAuthCookie(res, token) {
  res.cookie('token', token, {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    maxAge: TOKEN_MAX_AGE * 1000,
    path: '/',
  });
}

export function clearAuthCookie(res) {
  res.clearCookie('token', { path: '/' });
}
