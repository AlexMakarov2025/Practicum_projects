/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Александр Макаров
 * Дата: 04.03.2025г.
*/

-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Напишите ваш запрос здесь
WITH limits AS (
    -- Определяем выбросы по перцентилям
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_data AS (
    -- Фильтрация данных: исключение выбросов, только города и полные годы (2015-2018)
    SELECT 
        a.id, 
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        f.floor,
        f.kitchen_area,
        f.airports_nearest,
        f.parks_around3000,
        f.ponds_around3000,
        c.city,
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'Ленинградская область'
        END AS region
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    WHERE a.last_price > 0
        AND f.total_area > 0
        AND f.total_area < (SELECT total_area_limit FROM limits)
        AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
        AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
        AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
              AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
        AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31' -- Только полные годы
        AND t.type = 'город' -- Объявления в городах
),
categorized_data AS (
    -- Категоризация объявлений по времени активности
    SELECT
        region,
        CASE
            WHEN days_exposition IS NULL THEN 'другие'
            WHEN days_exposition BETWEEN 1 AND 30 THEN '1 месяц'
            WHEN days_exposition BETWEEN 31 AND 90 THEN '3 месяца'
            WHEN days_exposition BETWEEN 91 AND 180 THEN '6 месяцев'
            ELSE 'более 6 месяцев'
        END AS activity_category,
        last_price,
        total_area,
        rooms,
        balcony,
        ceiling_height,
        floor,
        kitchen_area,
        airports_nearest,
        parks_around3000,
        ponds_around3000
    FROM filtered_data
),
region_totals AS (
    -- Общее количество объявлений по регионам
    SELECT 
        region, 
        COUNT(*) AS total_ads
    FROM categorized_data
    GROUP BY region
),
final_data AS (
    -- Группировка по категориям времени активности
    SELECT
        c.region,
        c.activity_category,
        COUNT(*) AS ads_count,
        ROUND(AVG(c.last_price / c.total_area)::NUMERIC) AS sred_cena_za_metr, -- Средняя цена за квадратный метр
        ROUND(AVG(c.total_area)::NUMERIC, 2) AS srednyaya_ploschad, -- Средняя площадь
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.rooms) AS mediana_po_komnatam, -- Медиана по количеству комнат
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.balcony) AS mediana_po_balconam, -- Медиана по количеству балконов
        ROUND(AVG(c.ceiling_height)::NUMERIC, 2) AS srednyaya_vysota_potolkov, -- Средняя высота потолков
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.floor) AS mediana_etazhnosti, -- Медиана по этажу
        ROUND(AVG(c.kitchen_area)::NUMERIC, 2) AS srednyaya_ploschad_kuhni, -- Средняя площадь кухни
        ROUND(AVG(c.airports_nearest)::NUMERIC, 2) AS sred_rasstoyanie_do_avia, -- Среднее расстояние до аэропорта
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.parks_around3000) AS mediana_po_parkam, -- Медиана по паркам
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.ponds_around3000) AS median_po_vodoemam, -- Медиана по водоемам
        ROUND((COUNT(*) / r.total_ads::NUMERIC) * 100, 2) AS dolya_obyavlenij_v_regione-- Доля объявлений в регионе (%)
    FROM categorized_data c
    JOIN region_totals r ON c.region = r.region
    GROUP BY c.region, c.activity_category, r.total_ads
)
-- Итоговый запрос
SELECT *
FROM final_data
ORDER BY region, activity_category;

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Напишите ваш запрос здесь
WITH limits AS (
    -- Определяем выбросы по перцентилям
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_data AS (
    -- Фильтрация данных: исключение выбросов, только города и полные годы (2015-2018)
    SELECT 
        a.id, 
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.type t ON f.type_id = t.type_id
    WHERE a.last_price > 0
        AND f.total_area > 0
        AND f.total_area < (SELECT total_area_limit FROM limits)
        AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
        AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
        AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
              AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
        AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31' -- Только полные годы
        AND t.type = 'город' -- Только объявления в городах
),
published_ads AS (
    -- Данные по опубликованным объявлениям
    SELECT 
        EXTRACT(MONTH FROM first_day_exposition) AS month,
        COUNT(*) AS new_listings,
        ROUND(AVG(last_price / total_area)::NUMERIC) AS avg_price_per_sqm,
        ROUND(AVG(total_area)::NUMERIC,2) AS avg_area
    FROM filtered_data
    GROUP BY month
),
closed_ads AS (
    -- Данные по снятым объявлениям (по месяцам снятия)
    SELECT 
        EXTRACT(MONTH FROM first_day_exposition + days_exposition * INTERVAL '1 day') AS month,
        COUNT(*) AS closed_listings,
        ROUND(AVG(last_price / total_area)::NUMERIC) AS avg_price_per_sqm_closed,
        ROUND(AVG(total_area)::NUMERIC, 2) AS avg_area_closed
    FROM filtered_data
    WHERE days_exposition IS NOT NULL
    GROUP BY month
),
totals AS (
    -- Общее количество объявлений
    SELECT COUNT(*) AS total_ads FROM filtered_data
),
final_data AS (
    -- Объединение по опубликованным и снятым объявлениям
    SELECT 
        p.month,
        COALESCE(p.new_listings, 0) AS new_listings,
        COALESCE(c.closed_listings, 0) AS closed_listings,
        COALESCE(p.avg_price_per_sqm, 0) AS avg_price_per_sqm,
        COALESCE(p.avg_area, 0) AS avg_area,
        COALESCE(c.avg_price_per_sqm_closed, 0) AS avg_price_per_sqm_closed,
        COALESCE(c.avg_area_closed, 0) AS avg_area_closed,
        ROUND(COALESCE(p.new_listings, 0) * 100.0 / (SELECT total_ads FROM totals), 2) AS new_listings_pct,
        ROUND(COALESCE(c.closed_listings, 0) * 100.0 / (SELECT total_ads FROM totals), 2) AS closed_listings_pct
    FROM published_ads p
    FULL JOIN closed_ads c ON p.month = c.month
)
-- Итоговый запрос с ранжированием
SELECT
    TO_CHAR(TO_DATE(month::TEXT, 'MM'), 'TMMonth') AS month_name,
    new_listings,
    closed_listings,
    avg_price_per_sqm,
    avg_area,
    avg_price_per_sqm_closed,
    avg_area_closed,
    new_listings_pct,
    closed_listings_pct,
    RANK() OVER (ORDER BY new_listings DESC) AS new_listings_rank,
    RANK() OVER (ORDER BY closed_listings DESC) AS closed_listings_rank
FROM final_data
ORDER BY month;

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

-- Напишите ваш запрос здесь
WITH limits AS (
    -- Определяем выбросы по перцентилям
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_data AS (
  -- Фильтрация данных: исключение выбросов, только полные годы (2015-2018)
  SELECT 
      a.id, 
      a.first_day_exposition,
      a.days_exposition,
      a.last_price,
      f.total_area,
      c.city,
      t.type
  FROM real_estate.advertisement a
  JOIN real_estate.flats f ON a.id = f.id
  JOIN real_estate.city c ON f.city_id = c.city_id
  JOIN real_estate.type t ON f.type_id = t.type_id
  WHERE a.last_price > 0
      AND f.total_area > 0
      AND f.total_area < (SELECT total_area_limit FROM limits)
      AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
      AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
      AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
      AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
      AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31' -- Только полные годы
),
city_stats AS (
  -- Статистика по всем населённым пунктам (ранжирование выполняется до фильтрации)
  SELECT
      city,
      type,
      COUNT(*) AS total_listings,
      COUNT(*) FILTER (WHERE days_exposition IS NOT NULL) AS closed_listings,
      ROUND(AVG(last_price / total_area::numeric)) AS avg_price_per_sqm,
      ROUND(AVG(total_area::numeric), 2) AS avg_area,
      ROUND(AVG(days_exposition::numeric), 2) AS avg_days_on_market,
      NTILE(4) OVER (ORDER BY AVG(days_exposition)) AS speed_rank -- Ранжирование по скорости продажи (до фильтрации)
  FROM filtered_data
  GROUP BY city, type
)
-- Итоговый запрос с фильтрацией населенных пунктов (>50 объявлений)
SELECT
  city,
  type,
  CASE
      WHEN speed_rank = 1 THEN 'Очень быстро'
      WHEN speed_rank = 2 THEN 'Быстро'
      WHEN speed_rank = 3 THEN 'Медленно'
      WHEN speed_rank = 4 THEN 'Очень медленно'
  END AS speed_category,
  total_listings,
  closed_listings,
  ROUND((closed_listings::float / total_listings * 100)::numeric, 2) AS closed_percentage, -- Доля снятых объявлений
  ROUND(avg_price_per_sqm::numeric, 2) AS avg_price_per_sqm,
  ROUND(avg_area::numeric, 2) AS avg_area,
  ROUND(avg_days_on_market::numeric, 2) AS avg_days_on_market,
  speed_rank
FROM city_stats
WHERE city != 'Санкт-Петербург' 
  AND total_listings > 50 
ORDER BY total_listings DESC;