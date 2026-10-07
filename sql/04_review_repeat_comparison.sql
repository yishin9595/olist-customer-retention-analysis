with valid_orders as (

  select
    o.order_id,
    c.customer_unique_id,
    o.order_approved_at,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    row_number() over (
      partition by c.customer_unique_id
      order by o.order_approved_at, o.order_id
    ) as order_rank

  from `project_name.Brazilian_ECommerce_Olist.olist_orders_dataset` as o
  join `project_name.Brazilian_ECommerce_Olist.olist_customers_dataset` as c
    on o.customer_id = c.customer_id
  where o.order_status not in ('canceled', 'unavailable')
    and o.order_approved_at is not null
),

max_date as (

  select
    date(max(order_approved_at)) as data_max_date
  from valid_orders
),

order_payment as (

  select
    order_id,
    sum(payment_value) as order_value
  from `project_name.Brazilian_ECommerce_Olist.olist_order_payments_dataset`
  group by order_id
),

order_review as (

  select
    order_id,
    avg(review_score) as review_score
  from `project_name.Brazilian_ECommerce_Olist.olist_order_reviews_score`
  group by order_id
),

first_order as (

  select
    vo.customer_unique_id,
    vo.order_id as first_order_id,
    date(vo.order_approved_at) as first_order_date,
    date(vo.order_delivered_customer_date) as delivered_date,
    date(vo.order_estimated_delivery_date) as estimated_date,
    r.review_score

  from valid_orders as vo
  left join order_payment as op
    on vo.order_id = op.order_id
  left join order_review as r
    on vo.order_id = r.order_id
  where vo.order_rank = 1
),

second_order as (

  select
    customer_unique_id,
    date(order_approved_at) as second_order_date
  from valid_orders
  where order_rank = 2
),

customer_features as (

  select
    fo.customer_unique_id,
    fo.first_order_id,
    fo.first_order_date,
    fo.delivered_date,
    fo.estimated_date,
    fo.review_score,
    so.second_order_date,

    case
      when so.second_order_date is not null
        and date_diff(
          so.second_order_date,
          fo.first_order_date,
          day
        ) <= 90
        then 1

      else 0

    end as repeat_within_90d,

    case
      when fo.delivered_date is null
        or fo.estimated_date is null
        then '無配送資料'

      when fo.delivered_date > fo.estimated_date
        then '配送延遲'

      else '準時配送'

    end as delivery_status,

    case
      when fo.review_score is null
        then '無評論資料'

      when fo.review_score <= 3
        then '低評分'

      else '高評分'

    end as review_group

  from first_order as fo
  left join second_order as so
    on fo.customer_unique_id = so.customer_unique_id
)

select
  review_group,
  count(*) as customers_cnt,
  sum(repeat_within_90d) as repeaters_cnt,

  round(
    sum(repeat_within_90d) * 100.0 / count(*),
    2
  ) as repeat_90d_rate

from customer_features
cross join max_date
where first_order_date <= date_sub(
  data_max_date,
  interval 90 day
)

group by review_group
order by repeat_90d_rate desc;
