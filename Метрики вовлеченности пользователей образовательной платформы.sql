-- всего тестов
select count(id)
from test

-- всего задач
select count(id)
from problem

-- кол-во решаемых тестов и задач по когортам
with ts_agg as ( -- считаем количество решаемых тестов по юзерам
  select
    case when u.company_id is null then 'прочие' else 'студенты' end as cohort,
    ts.user_id,
    count(distinct ts.test_id) as cnt_ts
  from teststart ts
  join users u
  on u.id = ts.user_id
  where ts.user_id >= 94
  group by cohort, ts.user_id
), pr as ( -- делаем объединеную таблицу решаемых задач из coderun и codesubmit
  select distinct
    case when u.company_id is null then 'прочие' else 'студенты' end as cohort,
    cr.user_id,
    cr.problem_id
  from coderun cr
  join users u
  on u.id = cr.user_id
  where cr.user_id >= 94
  union
  select distinct
    case when u.company_id is null then 'прочие' else 'студенты' end as cohort,
    cs.user_id,
    cs.problem_id
  from codesubmit cs
  join users u
  on u.id = cs.user_id
  where cs.user_id >= 94
), pr_agg as ( -- считаем количество решаемых задач по юзерам
  select
    cohort,
    user_id,
    count(problem_id) as cnt_pr
  from pr
  group by cohort,user_id
), ts_res as (
    select -- считаем среднее и медиану по количеству решаемых тестов на юзера
        ts_agg.cohort,
        round(avg(ts_agg.cnt_ts),2) as tests_avg,
        percentile_disc(0.5) within group(order by ts_agg.cnt_ts) as tests_median
    from ts_agg
    group by ts_agg.cohort
), pr_res as (
    select -- считаем среднее и медиану по количеству решаемых задач на юзера
        pr_agg.cohort,
        round(avg(pr_agg.cnt_pr),2) as problems_avg,
        percentile_disc(0.5) within group(order by pr_agg.cnt_pr) as problems_median
    from pr_agg
    group by pr_agg.cohort
)
select
    ts_res.cohort as когорта,
    ts_res.tests_avg as тесты_среднее,
    ts_res.tests_median as тесты_медиана,
    pr_res.problems_avg as задачи_среднее,
    pr_res.problems_median as задачи_медиана
from ts_res
join pr_res
on ts_res.cohort = pr_res.cohort
order by когорта DESC

-- rolling retention 0, 3, 7, 14, 30 дней
with tmp as ( -- промежуточная таблица - расчет разницы в днях по когортам
    select
        extract (month from u.date_joined) as n,
        to_char(u.date_joined, 'Mon YYYY') as cohort,
        ue.entry_at::date - u.date_joined::date as diff,
        u.id
    from users u 
    join userentry ue 
    on u.id = ue.user_id
    where u.id >= 94 and (u.company_id != 1 or u.company_id is null) and extract (year from u.date_joined) > 2021
), rr_wide as ( -- rolling retention "широкая" таблица
    select
        n,
        cohort,
        count(distinct case when diff = 0 then id end)*100 / count(distinct case when diff = 0 then id end) as день_0,
        count(distinct case when diff >= 3 then id end)*100 / count(distinct case when diff = 0 then id end) as день_03,
        count(distinct case when diff >= 7 then id end)*100 / count(distinct case when diff = 0 then id end) as день_07,
        count(distinct case when diff >= 14 then id end)*100 / count(distinct case when diff = 0 then id end) as день_14,
        count(distinct case when diff >= 30 then id end)*100 / count(distinct case when diff = 0 then id end) as день_30
    from tmp
    group by n, cohort
)
select -- rolling retention "длинная" таблица
    n,
    cohort,
    'день_0' as day_retention,
    день_0 as value_retention
from rr_wide
union
select
    n,
    cohort,
    'день_03',
    день_03
from rr_wide
union
select
    n,
    cohort,
    'день_07',
    день_07
from rr_wide
union
select
    n,
    cohort,
    'день_14',
    день_14
from rr_wide
union
select
    n,
    cohort,
    'день_30',
    день_30
from rr_wide
order by n, day_retention

-- lifetime по когортам
with a as (
    select -- промежуточная таблица для расчета retention по когортам
        count(distinct user_id) as cnt,
        to_char(u2.date_joined, 'YYYY-MM') as cohort,
        extract(days from u.entry_at - u2.date_joined) as diff
    from userentry u 
    join users u2 
    on u.user_id = u2.id
    where u.user_id >= 94
    group by cohort, diff
), b as (
    select
        cohort,
        diff,
        cnt * 1.0 / first_value(cnt) over (partition by cohort order by diff) as rt --посчитали retention - какая доля людей относительно первого дня вернулась в продукт
    from a
)
select 
    cohort as когорты,
    sum(rt) as lifetime -- расчет lifetime как интеграла (площади под графиком) от retention
from b
group by cohort

-- распределение активности пользователей по времени суток
select 
    extract(hour from entry_at) as часы, 
    count(id) as количество_пользователей
from userentry
where user_id >= 94
group by часы
order by часы

-- распределение активности пользователей по дням недели
with tmp as (
select 
    extract(isodow from entry_at) as n,
    count(id) as количество_пользователей
from userentry
where user_id >= 94
group by n
)
select
    n,
    case when n = 1 then 'Понедельник' when n = 2 then 'Вторник' when n = 3 then 'Среда' when n = 4 then 'Четверг' when n = 5 then 'Пятница' when n = 6 then 'Суббота' when n = 7 then 'Воскресенье' end as дни_недели,
    количество_пользователей
from tmp 
order by n