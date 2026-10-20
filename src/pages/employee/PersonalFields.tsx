import { useI18n } from '../../i18n';
import { Input, Select } from '../../components/ui';
import { CountrySelect } from '../../components/pickers';
import type { Employee } from '../../lib/api';

export interface PersonalForm {
  full_name_en: string; full_name_ar: string; preferred_name: string; date_of_birth: string; gender: string;
  nationality: string; marital_status: string; civil_number: string; personal_email: string; work_email: string;
  mobile: string; alt_phone: string; address_line: string; city: string; wilayat: string; governorate: string; address_country: string;
}

export const emptyPersonal = (): PersonalForm => ({
  full_name_en: '', full_name_ar: '', preferred_name: '', date_of_birth: '', gender: '', nationality: '', marital_status: '',
  civil_number: '', personal_email: '', work_email: '', mobile: '', alt_phone: '', address_line: '', city: '', wilayat: '',
  governorate: '', address_country: 'OM',
});

export const personalFrom = (e: Employee): PersonalForm => ({
  full_name_en: e.full_name_en ?? '', full_name_ar: e.full_name_ar ?? '', preferred_name: e.preferred_name ?? '',
  date_of_birth: e.date_of_birth ?? '', gender: e.gender ?? '', nationality: e.nationality ?? '', marital_status: e.marital_status ?? '',
  civil_number: e.civil_number ?? '', personal_email: e.personal_email ?? '', work_email: e.work_email ?? '', mobile: e.mobile ?? '',
  alt_phone: e.alt_phone ?? '', address_line: e.address_line ?? '', city: e.city ?? '', wilayat: e.wilayat ?? '',
  governorate: e.governorate ?? '', address_country: e.address_country ?? '',
});

/** Every field is sent; blanks become null so the server can clear them. */
export const personalPayload = (p: PersonalForm): Record<string, string | null> => {
  const out: Record<string, string | null> = {};
  for (const [k, v] of Object.entries(p)) out[k] = v.trim() === '' ? null : v.trim();
  return out;
};

export function PersonalFields({ value: p, onChange }: { value: PersonalForm; onChange: (p: PersonalForm) => void }) {
  const { t } = useI18n();
  const set = (k: keyof PersonalForm) => (v: string) => onChange({ ...p, [k]: v });
  return (
    <div className="form-grid">
      <Input label={t('ef.full_name_en')} required value={p.full_name_en} onChange={(e) => set('full_name_en')(e.target.value)} autoComplete="off" />
      <Input label={t('ef.full_name_ar')} dir="rtl" lang="ar" value={p.full_name_ar} onChange={(e) => set('full_name_ar')(e.target.value)} autoComplete="off" />
      <CountrySelect label={t('emp.nationality')} nationality required value={p.nationality} onChange={(v) => set('nationality')(v ?? '')} />
      <Input label={t('ef.dob')} type="date" value={p.date_of_birth} onChange={(e) => set('date_of_birth')(e.target.value)} />
      <Select label={t('ef.gender')} value={p.gender} onChange={(e) => set('gender')(e.target.value)}>
        <option value="">{t('c.select')}</option>
        <option value="M">{t('ef.male')}</option>
        <option value="F">{t('ef.female')}</option>
      </Select>
      <Select label={t('ef.marital')} value={p.marital_status} onChange={(e) => set('marital_status')(e.target.value)}>
        <option value="">{t('c.select')}</option>
        {(['SINGLE', 'MARRIED', 'DIVORCED', 'WIDOWED'] as const).map((m) => <option key={m} value={m}>{t(`ef.${m}`)}</option>)}
      </Select>
      <Input label={t('ef.civil')} ltr value={p.civil_number} onChange={(e) => set('civil_number')(e.target.value.toUpperCase())} />
      <Input label={t('ef.preferred_name')} value={p.preferred_name} onChange={(e) => set('preferred_name')(e.target.value)} />
      <Input label={t('ef.mobile')} type="tel" ltr value={p.mobile} onChange={(e) => set('mobile')(e.target.value)} placeholder="+968 …" />
      <Input label={t('ef.alt_phone')} type="tel" ltr value={p.alt_phone} onChange={(e) => set('alt_phone')(e.target.value)} />
      <Input label={t('ef.work_email')} type="email" ltr value={p.work_email} onChange={(e) => set('work_email')(e.target.value)} />
      <Input label={t('ef.personal_email')} type="email" ltr value={p.personal_email} onChange={(e) => set('personal_email')(e.target.value)} />
      <Input label={t('ef.address')} className="span-2" value={p.address_line} onChange={(e) => set('address_line')(e.target.value)} />
      <Input label={t('ef.city')} value={p.city} onChange={(e) => set('city')(e.target.value)} />
      <Input label={t('ef.wilayat')} value={p.wilayat} onChange={(e) => set('wilayat')(e.target.value)} />
      <Input label={t('ef.governorate')} value={p.governorate} onChange={(e) => set('governorate')(e.target.value)} />
      <CountrySelect label={t('ef.address_country')} value={p.address_country} onChange={(v) => set('address_country')(v ?? '')} />
    </div>
  );
}
