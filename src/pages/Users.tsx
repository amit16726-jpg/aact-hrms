import { useState } from 'react';
import { api, type UserRow } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Loading, Modal, useAction, useAsync, useConfirm } from '../components/ui';
import { EmployeePicker } from '../components/pickers';
import { PageHead } from '../components/Layout';
import { fmtDateTime } from '../lib/format';

export default function UsersPage() {
  const { t, L } = useI18n();
  const { me, reload: reloadMe } = useSession();
  const users = useAsync(() => api.listUsers(), []);
  const roles = useAsync(() => api.listRoles(), []);
  const [editRoles, setEditRoles] = useState<{ user: UserRow; roles: string[] } | null>(null);
  const [link, setLink] = useState<{ user: UserRow; employeeId: string | null; label: string | null } | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();

  const roleName = (code: string) => {
    const r = roles.data?.roles.find((x) => x.code === code);
    return r ? L(r.name_en, r.name_ar) : code;
  };
  const after = (r: UserRow[] | undefined) => { if (r) { users.setData(r); void reloadMe(); } };

  if ((users.loading && !users.data) || (roles.loading && !roles.data)) return <Loading />;
  if (users.error) return <ErrorNote error={users.error} onRetry={users.reload} />;

  const perms = roles.data?.permissions ?? [];

  return (
    <div className="stack">
      <PageHead title={t('us.title')} sub={t('us.invite_hint')} />
      <section className="panel">
        {(users.data ?? []).length === 0 ? <Empty>—</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('us.email')}</th><th>{t('us.roles')}</th><th>{t('us.employee')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{(users.data ?? []).map((u) => (
              <tr key={u.user_id}>
                <td data-label={t('us.email')}>{u.email}{u.user_id === me?.user_id && <span className="muted"> ({t('us.you')})</span>}
                  <span className="sub">{u.display_name}, {fmtDateTime(u.created_at)}</span></td>
                <td data-label={t('us.roles')}>{u.roles.length ? <div className="row" style={{ gap: 4 }}>{u.roles.map((r) => <Badge key={r} tone="info">{roleName(r)}</Badge>)}</div> : <span className="muted">—</span>}</td>
                <td data-label={t('us.employee')}>{u.employee_no ? <>{u.employee_name}<span className="sub num">{u.employee_no}</span></> : <span className="muted">—</span>}</td>
                <td data-label={t('c.status')}><Badge tone={u.is_active ? 'ok' : 'bad'}>{u.is_active ? t('c.active') : t('c.inactive')}</Badge></td>
                <td className="r"><div className="row" style={{ justifyContent: 'flex-end', gap: 4 }}>
                  <Button small kind="ghost" onClick={() => setEditRoles({ user: u, roles: [...u.roles] })}>{t('us.edit_roles')}</Button>
                  <Button small kind="ghost" onClick={() => setLink({ user: u, employeeId: u.employee_id, label: u.employee_no ? `${u.employee_no} — ${u.employee_name}` : null })}>{t('us.link')}</Button>
                  {u.user_id !== me?.user_id && <Button small kind="ghost" onClick={async () => {
                    if ((await confirm.ask({ title: u.is_active ? t('us.deactivate') : t('us.activate'), body: u.email, danger: u.is_active })) === null) return;
                    after(await run(() => api.setUserActive(u.user_id, !u.is_active), t('c.saved')));
                  }}>{u.is_active ? t('us.deactivate') : t('us.activate')}</Button>}
                </div></td>
              </tr>))}
            </tbody></table></div>
        )}
      </section>

      <section className="panel">
        <div className="panel-head"><h2>{t('us.roles_matrix')}</h2></div>
        <div className="table-wrap"><table className="t">
          <thead><tr><th /> {(roles.data?.roles ?? []).map((r) => <th key={r.code} style={{ textAlign: 'center' }}>{L(r.name_en, r.name_ar)}</th>)}</tr></thead>
          <tbody>{perms.map((p) => (
            <tr key={p.code}>
              <td>{p.description}<span className="sub">{p.module}</span></td>
              {(roles.data?.roles ?? []).map((r) => <td key={r.code} style={{ textAlign: 'center' }}>{r.permissions.includes(p.code) ? '✓' : ''}</td>)}
            </tr>))}
          </tbody></table></div>
      </section>

      <Modal open={!!editRoles} title={`${t('us.edit_roles')}: ${editRoles?.user.email ?? ''}`} onClose={() => setEditRoles(null)}
        footer={<><Button onClick={() => setEditRoles(null)}>{t('c.cancel')}</Button>
          <Button kind="primary" busy={busy} onClick={async () => {
            if (!editRoles) return;
            const r = await run(() => api.setUserRoles(editRoles.user.user_id, editRoles.roles), t('c.saved'));
            if (r) { after(r); setEditRoles(null); }
          }}>{t('c.save')}</Button></>}>
        {editRoles && (
          <div className="stack">
            {(roles.data?.roles ?? []).map((r) => (
              <Check key={r.code} checked={editRoles.roles.includes(r.code)}
                label={<><b>{L(r.name_en, r.name_ar)}</b><span className="muted"> — {r.description}</span></>}
                onChange={(v) => setEditRoles({ ...editRoles, roles: v ? [...editRoles.roles, r.code] : editRoles.roles.filter((x) => x !== r.code) })} />
            ))}
          </div>
        )}
      </Modal>

      <Modal open={!!link} title={`${t('us.link')}: ${link?.user.email ?? ''}`} onClose={() => setLink(null)}
        footer={<>
          {link?.user.employee_id && <Button kind="danger" busy={busy} onClick={async () => {
            if (!link) return;
            const r = await run(() => api.linkUserEmployee(link.user.user_id, null), t('c.saved'));
            if (r) { after(r); setLink(null); }
          }}>{t('us.unlink')}</Button>}
          <span className="spacer" />
          <Button onClick={() => setLink(null)}>{t('c.cancel')}</Button>
          <Button kind="primary" busy={busy} disabled={!link?.employeeId} onClick={async () => {
            if (!link?.employeeId) return;
            const r = await run(() => api.linkUserEmployee(link.user.user_id, link.employeeId), t('c.saved'));
            if (r) { after(r); setLink(null); }
          }}>{t('c.save')}</Button></>}>
        {link && <EmployeePicker label={t('us.employee')} value={link.employeeId} valueLabel={link.label}
          onChange={(id, lbl) => setLink({ ...link, employeeId: id, label: lbl })} />}
      </Modal>
      {confirm.node}
    </div>
  );
}
