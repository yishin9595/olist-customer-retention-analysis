with valid_orders as (

  select
    o.order_id,
    c.customer_unique_id,
    o.order_approved_at,
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

second_order as (

  select
    customer_unique_id,
    date(order_approved_at) as second_order_date
  from valid_orders
  where order_rank = 2
),

first_order_items as (

  select
    vo.customer_unique_id,
    vo.order_id as first_order_id,
    date(vo.order_approved_at) as first_order_date,
    oi.order_item_id,
    oi.price,
    coalesce(
      p.product_category_name,
      'unknown'
    ) as product_category_name
  from valid_orders as vo
  join `project_name.Brazilian_ECommerce_Olist.olist_order_items_dataset` as oi
    on vo.order_id = oi.order_id
  left join `project_name.Brazilian_ECommerce_Olist.olist_products_dataset` as p
    on oi.product_id = p.product_id
  where vo.order_rank = 1
),

category_summary as (

  select
    customer_unique_id,
    first_order_id,
    first_order_date,
    case
      when product_category_name in (
        'artigos_de_natal'
      )
        then '季節性商品'

      when product_category_name in (
        'audio',
        'consoles_games',
        'eletronicos',
        'informatica_acessorios',
        'pcs',
        'telefonia',
        'telefonia_fixa'
      )
        then '3C與電子產品'

      when product_category_name in (
        'cama_mesa_banho',
        'casa_conforto',
        'casa_construcao',
        'eletrodomesticos',
        'eletroportateis',
        'moveis_cozinha_area_de_servico_jantar_e_jardim',
        'moveis_decoracao',
        'moveis_escritorio',
        'moveis_sala',
        'utilidades_domesticas'
      )
        then '家居與家電'

      when product_category_name in (
        'alimentos',
        'alimentos_bebidas',
        'bebidas',
        'bebes',
        'beleza_saude',
        'perfumaria',
        'pet_shop'
      )
        then '民生與日常用品'

      when product_category_name in (
        'fashion_bolsas_e_acessorios',
        'fashion_calcados',
        'fashion_underwear_e_moda_praia',
        'malas_acessorios'
      )
        then '服飾與配件'

      when product_category_name in (
        'esporte_lazer',
        'brinquedos',
        'livros_interesse_geral',
        'livros_tecnicos',
        'artes'
      )
        then '休閒與興趣'

      when product_category_name in (
        'automotivo',
        'construcao_ferramentas_construcao',
        'construcao_ferramentas_jardim',
        'construcao_ferramentas_iluminacao',
        'construcao_ferramentas_seguranca',
        'ferramentas_jardim',
        'industria_comercio_e_negocios',
        'agro_industria_e_comercio'
      )
        then '汽車與工具'

      else '其他'
    end as product_group,
    sum(price) as category_value,
    count(*) as category_item_cnt
  from first_order_items
  group by
    customer_unique_id,
    first_order_id,
    first_order_date,
    product_category_name
),

primary_product_group as (

  select
    customer_unique_id,
    first_order_id,
    first_order_date,
    product_group,
    row_number() over (
      partition by customer_unique_id
      order by category_item_cnt desc, category_value desc
    ) as group_rank
  from category_summary
),

customer_result as (

  select
    ppg.customer_unique_id,
    ppg.product_group,
    ppg.first_order_date,
    so.second_order_date,
    case
      when so.second_order_date is not null
        and date_diff(
          so.second_order_date,
          ppg.first_order_date,
          day
        ) <= 90
        then 1
      else 0
    end as repeat_within_90d
  from primary_product_group as ppg
  left join second_order as so
    on ppg.customer_unique_id = so.customer_unique_id
  where ppg.group_rank = 1
),

eligible_customers as (

  select
    cr.*
  from customer_result as cr
  cross join max_date
  where cr.first_order_date <= date_sub(
    data_max_date,
    interval 90 day
  )
),

group_summary as (

  select
    product_group,
    count(*) as customer_cnt,
    sum(repeat_within_90d) as repeaters_cnt,
    count(*) - sum(repeat_within_90d) as lost_customers,
    round(
      sum(repeat_within_90d) * 100.0 / count(*),
      2
    ) as repeat_90d_rate,
    round(
      (count(*) - sum(repeat_within_90d)) * 100.0 / count(*),
      2
    ) as lost_rate
  from eligible_customers
  group by product_group
)

select
  product_group,
  customer_cnt,
  repeaters_cnt,
  lost_customers,
  repeat_90d_rate,
  lost_rate,
  round(
    lost_customers * 100.0
    / sum(lost_customers) over (),
    2
  ) as lost_customer_share
from group_summary
order by lost_customer_share desc;
