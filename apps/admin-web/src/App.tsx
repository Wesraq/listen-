import { FormEvent, useEffect, useMemo, useState } from 'react';
import {
  ClipboardList,
  FileStack,
  LayoutDashboard,
  LogOut,
  Shield,
  Users,
  Wallet,
} from 'lucide-react';

import {
  AdminApiError,
  AdminUser,
  AdminUserListItem,
  AdminUserProfile,
  decideModeration,
  decidePayout,
  getAdSettlements,
  getAudit,
  getModeration,
  getOverview,
  getPayouts,
  getUserProfile,
  getUsers,
  login,
  setCreatorStatus,
} from './api';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

type Tab = 'overview' | 'users' | 'moderation' | 'payouts' | 'audit';

const NAV: Array<{ id: Tab; label: string; icon: typeof LayoutDashboard }> = [
  { id: 'overview', label: 'Overview', icon: LayoutDashboard },
  { id: 'users', label: 'Users & creators', icon: Users },
  { id: 'moderation', label: 'Moderation', icon: FileStack },
  { id: 'payouts', label: 'Finance', icon: Wallet },
  { id: 'audit', label: 'Audit logs', icon: ClipboardList },
];

export function App() {
  const [token, setToken] = useState(() => localStorage.getItem('listen.admin.token') ?? '');
  const [admin, setAdmin] = useState<AdminUser | null>(() => {
    const raw = localStorage.getItem('listen.admin.user');
    return raw ? (JSON.parse(raw) as AdminUser) : null;
  });
  const [tab, setTab] = useState<Tab>('overview');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [overview, setOverview] = useState<Awaited<ReturnType<typeof getOverview>> | null>(null);
  const [users, setUsers] = useState<AdminUserListItem[]>([]);
  const [selectedUid, setSelectedUid] = useState<string | null>(null);
  const [profile, setProfile] = useState<AdminUserProfile | null>(null);
  const [profileBusy, setProfileBusy] = useState(false);
  const [moderation, setModeration] = useState<Array<Record<string, string>>>([]);
  const [payouts, setPayouts] = useState<Array<Record<string, string | number>>>([]);
  const [adSettlements, setAdSettlements] = useState<
    Array<{
      id: string;
      at: string;
      currency: string;
      titleId: string;
      creatorUid: string;
      grossMinor: number;
      creatorShareMinor: number;
      platformShareMinor: number;
    }>
  >([]);
  const [audit, setAudit] = useState<Array<Record<string, string>>>([]);

  const signedIn = Boolean(token && admin);
  const initials = (admin?.displayName ?? 'LA')
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  useEffect(() => {
    if (!signedIn) return;
    void refresh();
  }, [signedIn, tab]);

  function clearSession(message?: string) {
    localStorage.removeItem('listen.admin.token');
    localStorage.removeItem('listen.admin.user');
    setToken('');
    setAdmin(null);
    if (message) setError(message);
  }

  async function refresh() {
    if (!token) return;
    setError(null);
    try {
      const nextOverview = await getOverview(token);
      setOverview(nextOverview);
      if (tab === 'users') {
        const nextUsers = (await getUsers(token)).items;
        setUsers(nextUsers);
        if (selectedUid) {
          setProfile(await getUserProfile(token, selectedUid));
        }
      }
      if (tab === 'moderation') setModeration((await getModeration(token)).items);
      if (tab === 'payouts') {
        setPayouts((await getPayouts(token)).items);
        setAdSettlements((await getAdSettlements(token)).items);
      }
      if (tab === 'audit') setAudit((await getAudit(token)).items);
    } catch (err) {
      if (err instanceof AdminApiError && err.isUnauthorized) {
        clearSession('Session expired after API restart. Sign in again.');
        return;
      }
      setError(err instanceof Error ? err.message : 'Failed to load admin data');
    }
  }

  async function onLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const email = String(form.get('email') ?? '');
    const password = String(form.get('password') ?? '');
    setBusy(true);
    setError(null);
    try {
      const session = await login(email, password);
      localStorage.setItem('listen.admin.token', session.token);
      localStorage.setItem('listen.admin.user', JSON.stringify(session.admin));
      setToken(session.token);
      setAdmin(session.admin);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setBusy(false);
    }
  }

  function signOut() {
    clearSession();
  }

  async function openProfile(uid: string) {
    if (!token) return;
    setSelectedUid(uid);
    setProfileBusy(true);
    setError(null);
    try {
      setProfile(await getUserProfile(token, uid));
    } catch (err) {
      if (err instanceof AdminApiError && err.isUnauthorized) {
        clearSession('Session expired after API restart. Sign in again.');
        return;
      }
      setError(err instanceof Error ? err.message : 'Failed to load user profile');
      setProfile(null);
    } finally {
      setProfileBusy(false);
    }
  }

  const money = useMemo(
    () => (minor: number, currency = 'ZMW') => `${currency} ${(Number(minor) / 100).toFixed(2)}`,
    [],
  );

  const title = NAV.find((item) => item.id === tab)?.label ?? 'Admin';

  if (!signedIn) {
    return (
      <div className="login-shell">
        <Card className="login-card border shadow-[var(--surface-shadow)]">
          <CardHeader>
            <div className="brand text-[32px]">
              listen<span className="brand-plus">+</span>
            </div>
            <CardTitle className="pt-2 text-xl">Admin console</CardTitle>
            <CardDescription>
              Same Listen+ design system as the mobile-first web reference. Sign in with the seeded
              ops account.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form className="space-y-4" onSubmit={onLogin}>
              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input id="email" name="email" type="email" defaultValue="admin@listen.plus" required />
              </div>
              <div className="space-y-2">
                <Label htmlFor="password">Password</Label>
                <Input
                  id="password"
                  name="password"
                  type="password"
                  defaultValue="ListenAdmin1!"
                  required
                />
              </div>
              {error ? <p className="text-sm text-destructive">{error}</p> : null}
              <Button className="w-full" type="submit" disabled={busy}>
                {busy ? 'Signing in…' : 'Sign in'}
              </Button>
              <p className="text-xs text-muted-foreground">
                Seeded: admin@listen.plus / ListenAdmin1!
              </p>
            </form>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="app-layout">
      <aside className="sidebar">
        <div className="brand">
          listen<span className="brand-plus">+</span>
        </div>
        <div className="nav-caption">Operations</div>
        <nav>
          {NAV.map((item) => {
            const Icon = item.icon;
            const count =
              item.id === 'moderation'
                ? overview?.moderationQueue
                : item.id === 'payouts'
                  ? overview?.payoutQueue
                  : item.id === 'users'
                    ? overview?.pendingCreators
                    : undefined;
            return (
              <button
                key={item.id}
                type="button"
                className={`nav-item${tab === item.id ? ' selected' : ''}`}
                onClick={() => setTab(item.id)}
              >
                <Icon size={18} />
                <span>{item.label}</span>
                {typeof count === 'number' && count > 0 ? (
                  <span className="nav-count">{count}</span>
                ) : null}
              </button>
            );
          })}
        </nav>
        <div className="sidebar-bottom">
          <div className="prototype-label">
            <span />
            Admin prototype
          </div>
          <div className="sidebar-account">
            <div className="avatar">{initials}</div>
            <div>
              <b>{admin?.displayName}</b>
              <small>{admin?.role}</small>
            </div>
          </div>
        </div>
      </aside>

      <div className="main-column">
        <header className="topbar">
          <div className="breadcrumb">
            Admin <span>/</span> <b>{title}</b>
          </div>
          <div className="topbar-actions">
            <div className="market">
              <Shield size={14} />
              Zambia · ZMW
            </div>
            <Button variant="outline" size="sm" onClick={signOut}>
              <LogOut size={14} />
              Sign out
            </Button>
          </div>
        </header>

        <main className="page-content">
          <div className="page-intro">
            <div>
              <div className="eyebrow">Listen+ ops</div>
              <h1>{title}</h1>
              <p>Moderate creators, content and payouts for the Zambia market.</p>
            </div>
          </div>

          {error ? (
            <Card className="mb-4 border-destructive/30">
              <CardContent className="pt-6 text-sm text-destructive">{error}</CardContent>
            </Card>
          ) : null}

          {tab === 'overview' && overview ? (
            <div className="metric-grid">
              <div className="metric-card">
                <span>Pending creators</span>
                <strong>{overview.pendingCreators}</strong>
              </div>
              <div className="metric-card">
                <span>Moderation queue</span>
                <strong>{overview.moderationQueue}</strong>
              </div>
              <div className="metric-card">
                <span>Payout queue</span>
                <strong>{overview.payoutQueue}</strong>
              </div>
              <div className="metric-card">
                <span>Payment exceptions</span>
                <strong>{overview.paymentExceptions}</strong>
              </div>
              <div className="metric-card">
                <span>Users</span>
                <strong>{overview.users}</strong>
              </div>
              <div className="metric-card">
                <span>Ad settlements</span>
                <strong>{overview.adSettlements ?? 0}</strong>
              </div>
              <div className="metric-card">
                <span>Ad platform share</span>
                <strong>
                  {money(overview.advertisingRevenueMinor ?? 0, overview.market.currency)}
                </strong>
              </div>
            </div>
          ) : null}

          {tab === 'users' ? (
            <div className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
              <div className="panel">
                <div className="mb-3 flex items-center justify-between">
                  <div>
                    <h3 className="text-base font-semibold">Users & creators</h3>
                    <p className="text-sm text-muted-foreground">
                      Open a row for the full account profile, library and Studio activity.
                    </p>
                  </div>
                </div>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>Email</TableHead>
                      <TableHead>Market</TableHead>
                      <TableHead>Role</TableHead>
                      <TableHead>Creator</TableHead>
                      <TableHead>Content</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {users.map((user) => (
                      <TableRow
                        key={user.uid}
                        className={selectedUid === user.uid ? 'bg-muted/40' : undefined}
                      >
                        <TableCell className="font-medium">
                          <button
                            type="button"
                            className="text-left hover:underline"
                            onClick={() => void openProfile(user.uid)}
                          >
                            {user.displayName}
                          </button>
                          <div className="text-xs text-muted-foreground">{user.uid}</div>
                        </TableCell>
                        <TableCell>{user.email}</TableCell>
                        <TableCell>{user.market}</TableCell>
                        <TableCell>
                          <Badge variant="secondary">{user.role}</Badge>
                        </TableCell>
                        <TableCell>
                          <Badge variant={user.creatorStatus === 'approved' ? 'default' : 'outline'}>
                            {user.creatorStatus}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs text-muted-foreground">
                          {user.draftsCount ?? 0} drafts · {user.liveCount ?? 0} live
                          <br />
                          {user.ownedCount ?? 0} owned · {user.savedCount ?? 0} saved
                        </TableCell>
                        <TableCell className="space-x-2 text-right">
                          <Button size="sm" variant="outline" onClick={() => void openProfile(user.uid)}>
                            Profile
                          </Button>
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() =>
                              void setCreatorStatus(token, user.uid, 'approved').then(async () => {
                                await refresh();
                                await openProfile(user.uid);
                              })
                            }
                          >
                            Approve
                          </Button>
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={() =>
                              void setCreatorStatus(token, user.uid, 'rejected', 'Demo rejection').then(
                                async () => {
                                  await refresh();
                                  await openProfile(user.uid);
                                },
                              )
                            }
                          >
                            Reject
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="panel">
                {!selectedUid ? (
                  <div className="text-sm text-muted-foreground">
                    Select a user to view the full profile.
                  </div>
                ) : profileBusy || !profile ? (
                  <div className="text-sm text-muted-foreground">Loading profile…</div>
                ) : (
                  <div className="space-y-4">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <h3 className="text-lg font-semibold">{profile.profile.displayName}</h3>
                        <p className="text-sm text-muted-foreground">{profile.profile.email}</p>
                      </div>
                      <Button size="sm" variant="ghost" onClick={() => { setSelectedUid(null); setProfile(null); }}>
                        Close
                      </Button>
                    </div>

                    <div className="grid grid-cols-2 gap-2 text-sm">
                      <div className="rounded-md border p-3">
                        <div className="text-muted-foreground">UID</div>
                        <div className="break-all font-medium">{profile.profile.uid}</div>
                      </div>
                      <div className="rounded-md border p-3">
                        <div className="text-muted-foreground">Market</div>
                        <div className="font-medium">{profile.profile.market}</div>
                      </div>
                      <div className="rounded-md border p-3">
                        <div className="text-muted-foreground">Role</div>
                        <div className="font-medium">{profile.profile.role}</div>
                      </div>
                      <div className="rounded-md border p-3">
                        <div className="text-muted-foreground">Creator status</div>
                        <div className="font-medium">{profile.profile.creatorStatus}</div>
                      </div>
                      <div className="rounded-md border p-3 col-span-2">
                        <div className="text-muted-foreground">Joined</div>
                        <div className="font-medium">{profile.profile.createdAt}</div>
                      </div>
                    </div>

                    <div>
                      <h4 className="mb-2 text-sm font-semibold">Library</h4>
                      <p className="text-sm text-muted-foreground">
                        Owned {profile.library.ownedCount}: {profile.library.ownedIds.join(', ') || '—'}
                      </p>
                      <p className="text-sm text-muted-foreground">
                        Saved {profile.library.savedCount}: {profile.library.savedIds.join(', ') || '—'}
                      </p>
                    </div>

                    <div>
                      <h4 className="mb-2 text-sm font-semibold">
                        Studio drafts ({profile.studio.draftsCount}) · submitted{' '}
                        {profile.studio.submittedCount} · live {profile.studio.liveCount}
                      </h4>
                      {profile.studio.drafts.length === 0 ? (
                        <p className="text-sm text-muted-foreground">No Studio drafts yet.</p>
                      ) : (
                        <div className="space-y-2">
                          {profile.studio.drafts.map((draft) => (
                            <div key={draft.id} className="rounded-md border p-3 text-sm">
                              <div className="font-medium">{draft.title}</div>
                              <div className="text-muted-foreground">
                                {draft.format} · {draft.status} · {draft.priceLabel || 'No price'}
                              </div>
                              {draft.mediaName ? (
                                <div className="text-xs text-muted-foreground">Media: {draft.mediaName}</div>
                              ) : null}
                              {draft.publishedTitleId ? (
                                <div className="text-xs text-muted-foreground">
                                  Catalogue id: {draft.publishedTitleId}
                                </div>
                              ) : null}
                            </div>
                          ))}
                        </div>
                      )}
                    </div>

                    <div>
                      <h4 className="mb-2 text-sm font-semibold">Sales</h4>
                      <p className="text-sm">
                        Gross {profile.sales.currency} {(profile.sales.grossSalesMinor / 100).toFixed(2)} ·
                        Available {(profile.sales.availableMinor / 100).toFixed(2)} · Pending{' '}
                        {(profile.sales.pendingMinor / 100).toFixed(2)}
                      </p>
                      {profile.sales.recent.length > 0 ? (
                        <ul className="mt-2 space-y-1 text-xs text-muted-foreground">
                          {profile.sales.recent.map((sale) => (
                            <li key={String(sale.id)}>
                              {String(sale.titleName)} · {String(sale.currency)}{' '}
                              {(Number(sale.grossMinor) / 100).toFixed(2)}
                            </li>
                          ))}
                        </ul>
                      ) : null}
                    </div>
                  </div>
                )}
              </div>
            </div>
          ) : null}

          {tab === 'moderation' ? (
            <div className="panel">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Title</TableHead>
                    <TableHead>Creator</TableHead>
                    <TableHead>Format</TableHead>
                    <TableHead>Price</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {moderation.map((item) => (
                    <TableRow key={item.id}>
                      <TableCell>
                        <div className="font-medium">{item.title}</div>
                        {item.mediaName ? (
                          <div className="text-xs text-muted-foreground">{item.mediaName}</div>
                        ) : null}
                      </TableCell>
                      <TableCell>{item.creatorName}</TableCell>
                      <TableCell>{item.format}</TableCell>
                      <TableCell className="text-sm">{item.priceLabel ?? '—'}</TableCell>
                      <TableCell>
                        <Badge variant="outline">{item.status}</Badge>
                      </TableCell>
                      <TableCell className="space-x-2 text-right">
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() =>
                            void decideModeration(token, item.id, 'approved').then(() => {
                              setError(null);
                              return refresh();
                            })
                          }
                        >
                          Approve
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() =>
                            void decideModeration(
                              token,
                              item.id,
                              'changes_requested',
                              'Need clearer rights scope',
                            ).then(refresh)
                          }
                        >
                          Changes
                        </Button>
                        <Button
                          size="sm"
                          variant="destructive"
                          onClick={() =>
                            void decideModeration(token, item.id, 'rejected', 'Rights unclear').then(refresh)
                          }
                        >
                          Reject
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          ) : null}

          {tab === 'payouts' ? (
            <div className="space-y-6">
              <div className="panel">
                <h2 className="mb-3 text-sm font-medium">Cashouts</h2>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Creator</TableHead>
                      <TableHead>Amount</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {payouts.map((item) => (
                      <TableRow key={String(item.id)}>
                        <TableCell className="font-medium">{item.creatorName}</TableCell>
                        <TableCell>
                          {money(Number(item.amountMinor), String(item.currency))}
                        </TableCell>
                        <TableCell>
                          <Badge variant="outline">{String(item.status)}</Badge>
                        </TableCell>
                        <TableCell className="space-x-2 text-right">
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() =>
                              void decidePayout(token, String(item.id), 'approved').then(refresh)
                            }
                          >
                            Approve
                          </Button>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() =>
                              void decidePayout(
                                token,
                                String(item.id),
                                'settled',
                                'DEMO-SETTLE-001',
                              ).then(refresh)
                            }
                          >
                            Settle
                          </Button>
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={() =>
                              void decidePayout(token, String(item.id), 'rejected').then(refresh)
                            }
                          >
                            Reject
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
              <div className="panel">
                <h2 className="mb-3 text-sm font-medium">Advertising settlements (ledger)</h2>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>When</TableHead>
                      <TableHead>Title</TableHead>
                      <TableHead>Creator</TableHead>
                      <TableHead>Gross</TableHead>
                      <TableHead>Creator 55%</TableHead>
                      <TableHead>Platform 45%</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {adSettlements.length === 0 ? (
                      <TableRow>
                        <TableCell colSpan={6} className="text-muted-foreground">
                          No ad settlements yet — completions post here after verified AdMob rewards.
                        </TableCell>
                      </TableRow>
                    ) : (
                      adSettlements.map((item) => (
                        <TableRow key={item.id}>
                          <TableCell>{new Date(item.at).toLocaleString()}</TableCell>
                          <TableCell className="font-mono text-xs">{item.titleId}</TableCell>
                          <TableCell className="font-mono text-xs">
                            {item.creatorUid.slice(0, 10)}
                          </TableCell>
                          <TableCell>{money(item.grossMinor, item.currency)}</TableCell>
                          <TableCell>{money(item.creatorShareMinor, item.currency)}</TableCell>
                          <TableCell>{money(item.platformShareMinor, item.currency)}</TableCell>
                        </TableRow>
                      ))
                    )}
                  </TableBody>
                </Table>
              </div>
            </div>
          ) : null}

          {tab === 'audit' ? (
            <div className="panel">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>When</TableHead>
                    <TableHead>Actor</TableHead>
                    <TableHead>Action</TableHead>
                    <TableHead>Target</TableHead>
                    <TableHead>Reason</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {audit.map((item) => (
                    <TableRow key={item.id}>
                      <TableCell>{new Date(item.at).toLocaleString()}</TableCell>
                      <TableCell>{item.actorEmail}</TableCell>
                      <TableCell>{item.action}</TableCell>
                      <TableCell>{item.target}</TableCell>
                      <TableCell className="text-muted-foreground">{item.reason || '—'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          ) : null}
        </main>
      </div>
    </div>
  );
}
