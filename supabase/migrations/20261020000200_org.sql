-- AACT HRMS — 002 organisation masters

create table if not exists hr.countries (
  code           char(2) primary key,
  name_en        text not null,
  name_ar        text not null,
  nationality_en text not null,
  nationality_ar text not null,
  sort           int not null default 100
);

insert into hr.countries(code, name_en, name_ar, nationality_en, nationality_ar, sort) values
  ('OM','Oman','عُمان','Omani','عُماني',1),
  ('IN','India','الهند','Indian','هندي',10),
  ('PK','Pakistan','باكستان','Pakistani','باكستاني',11),
  ('BD','Bangladesh','بنغلاديش','Bangladeshi','بنغلاديشي',12),
  ('NP','Nepal','نيبال','Nepali','نيبالي',13),
  ('LK','Sri Lanka','سريلانكا','Sri Lankan','سريلانكي',14),
  ('PH','Philippines','الفلبين','Filipino','فلبيني',15),
  ('EG','Egypt','مصر','Egyptian','مصري',16),
  ('JO','Jordan','الأردن','Jordanian','أردني',17),
  ('SD','Sudan','السودان','Sudanese','سوداني',18),
  ('YE','Yemen','اليمن','Yemeni','يمني',19),
  ('SY','Syria','سوريا','Syrian','سوري',20),
  ('LB','Lebanon','لبنان','Lebanese','لبناني',21),
  ('TN','Tunisia','تونس','Tunisian','تونسي',22),
  ('MA','Morocco','المغرب','Moroccan','مغربي',23),
  ('AE','United Arab Emirates','الإمارات','Emirati','إماراتي',30),
  ('SA','Saudi Arabia','السعودية','Saudi','سعودي',31),
  ('KW','Kuwait','الكويت','Kuwaiti','كويتي',32),
  ('QA','Qatar','قطر','Qatari','قطري',33),
  ('BH','Bahrain','البحرين','Bahraini','بحريني',34),
  ('ID','Indonesia','إندونيسيا','Indonesian','إندونيسي',40),
  ('CN','China','الصين','Chinese','صيني',41),
  ('GB','United Kingdom','المملكة المتحدة','British','بريطاني',50),
  ('US','United States','الولايات المتحدة','American','أمريكي',51),
  ('ZA','South Africa','جنوب أفريقيا','South African','جنوب أفريقي',52),
  ('KE','Kenya','كينيا','Kenyan','كيني',53),
  ('UG','Uganda','أوغندا','Ugandan','أوغندي',54),
  ('ET','Ethiopia','إثيوبيا','Ethiopian','إثيوبي',55)
on conflict (code) do nothing;

create table if not exists hr.legal_entities (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name_en     text not null,
  name_ar     text,
  cr_number   text,
  mol_establishment_no text,
  sector      text,
  country     char(2) not null default 'OM' references hr.countries(code),
  currency    char(3) not null default 'OMR',
  address     text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists hr.locations (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references hr.legal_entities(id),
  code        text not null,
  name_en     text not null,
  name_ar     text,
  location_type text not null default 'FACTORY'
              check (location_type in ('FACTORY','OFFICE','WAREHOUSE','SITE','ACCOMMODATION')),
  address     text,
  city        text,
  governorate text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (entity_id, code)
);

create table if not exists hr.cost_centres (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references hr.legal_entities(id),
  code        text not null,
  name_en     text not null,
  name_ar     text,
  gl_code     text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (entity_id, code)
);

create table if not exists hr.departments (
  id             uuid primary key default gen_random_uuid(),
  entity_id      uuid not null references hr.legal_entities(id),
  code           text not null,
  name_en        text not null,
  name_ar        text,
  parent_id      uuid references hr.departments(id),
  cost_centre_id uuid references hr.cost_centres(id),
  head_employee_id uuid,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (entity_id, code),
  check (parent_id is null or parent_id <> id)
);

create table if not exists hr.grades (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references hr.legal_entities(id),
  code        text not null,
  name_en     text not null,
  name_ar     text,
  level       int not null default 1,
  min_basic   numeric(12,3),
  max_basic   numeric(12,3),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (entity_id, code),
  check (min_basic is null or min_basic >= 0),
  check (min_basic is null or max_basic is null or min_basic <= max_basic)
);

create table if not exists hr.job_titles (
  id                  uuid primary key default gen_random_uuid(),
  entity_id           uuid not null references hr.legal_entities(id),
  code                text not null,
  name_en             text not null,
  name_ar             text,
  profession_code     text,          -- Ministry of Labour occupation code, as issued to the company
  omani_only          boolean not null default false,
  omani_only_source   text,          -- decision / circular number and date
  omani_only_verified boolean not null default false,
  description         text,
  required_qualifications text,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (entity_id, code),
  check (not omani_only or coalesce(omani_only_source,'') <> '')
);

create table if not exists hr.employee_categories (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references hr.legal_entities(id),
  code        text not null,
  name_en     text not null,
  name_ar     text,
  pay_basis   text not null default 'MONTHLY' check (pay_basis in ('MONTHLY','DAILY','HOURLY')),
  counts_for_omanisation boolean not null default true,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (entity_id, code)
);

create index if not exists departments_parent on hr.departments(parent_id);

select hr.attach_audit();
select hr.secure_api();
