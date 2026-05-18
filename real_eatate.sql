

/* Проект: Анализ рынка недвижимости Санкт-Петербурга и Ленинградской области
 * Цель проекта: провести анализ объявлений о продаже жилой недвижимости в Санкт-Петербурге и Ленинградской области
 * для планирования эффективной бизнес-стратегии и выхода на рынок
 * 
 * Автор: Ластовкина Татьяна
 * Дата: 29.06.2025
 * 
 * Аd-hoc задачи
 * 1. Определить по времени активности наиболее привлекательные сегменты недвижимости Санкт-Петербурга и 
 * городов Ленинградской области.
 * 2. Понять сезонные тенденции на рынке Санкт-Петербурга и городов Ленинградской области для планирования
 *  маркетинговых кампаний и выбора сроков для выхода на рынок.
*/

/*Задача 1. Разделить объявления на категории по количеству дней активности. 
* Для каждой категории изучить количество продаваемых квартир, а также их параметры, 
* включая среднюю стоимость квадратного метра, среднюю площадь недвижимости, количество комнат и балконов.
* Сравнить объявления Санкт-Петербурга и городов Ленинградской области.
*/

    
-- Убираем аномальные значения из real_estate.flats 
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
--Высчитаем стоимость за кв.метр
    sq_m_price_data AS (
    SELECT id,
    	last_price/total_area AS price_per_sqm
    FROM real_estate.flats
    LEFT JOIN real_estate.advertisement USING (id)),
-- Высчитаем выбросы для стоимости за кв.метр
    limits_2 AS (
    SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY price_per_sqm) AS price_per_sqm_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY price_per_sqm) AS price_per_sqm_limit_l
     FROM sq_m_price_data),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats 
    JOIN sq_m_price_data USING (id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND (price_per_sqm < (SELECT price_per_sqm_limit_h FROM limits_2) AND price_per_sqm > (SELECT price_per_sqm_limit_l FROM limits_2))    
    ),
-- Выведем объявления без выбросов, только по Санкт-Петербургу и городам Лен.области и за полные года 2015-2018
flats_filtered_data AS (SELECT *
FROM real_estate.flats 
JOIN real_estate.advertisement USING (id)
JOIN sq_m_price_data USING (id)
WHERE id IN (SELECT * FROM filtered_id)
		AND type_id='F8EM' --оставляем объявления только в городах
		AND EXTRACT (YEAR FROM first_day_exposition) IN (2015, 2016, 2017, 2018) --оставляем объявления за полные года 2015-2018
		),
-- Делим новые данные на категории Санкт-Петербург и Ленингр.обл и по длительности побликации
ads_category AS (
	SELECT *,
		CASE --выделяем категории по региону
			WHEN ffd.city_id='6X8I'
		    THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл'
		END AS region,
		CASE --выделяем категории по длительности объявления
			WHEN ffd.days_exposition<=30
		    THEN '1-до месяца'
		    WHEN ffd.days_exposition<=90
		    THEN '2-до трех месяцев'
		    WHEN ffd.days_exposition<=180
		    THEN '3-до полугода'
		    WHEN ffd.days_exposition>180
		    THEN '4-более полугода'
			ELSE '5-не снято'
		END AS ads_duration
	FROM flats_filtered_data AS ffd)
--Основной запрос		      
SELECT 
	ac.region,
	ac.ads_duration,
	COUNT(ac.id) AS ads_amount,
	ROUND(COUNT(ac.id)::numeric/(SUM(COUNT(ac.id)) OVER (PARTITION BY ac.region)),2) AS ads_part, --доля объявлений от общего числа
	ROUND(AVG(ac.price_per_sqm::numeric)) AS avg_price_per_sqm,
	ROUND(AVG(ac.total_area::numeric),2) AS avg_total_area,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ac.rooms) AS mediana_rooms,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ac.floor) AS mediana_floor,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ac.floors_total) AS mediana_total_floor,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ac.balcony) AS mediana_balcony
FROM ads_category AS ac
GROUP BY ac.region,
		 ac.ads_duration
ORDER BY ac.region DESC,
		ac.ads_duration; 
/*
ВЫВОД:

|region         |ads_duration     |ads_amount|ads_part|avg_price_per_sqm|avg_total_area|mediana_rooms|mediana_floor|mediana_total_floor|mediana_balcony|
|---------------|-----------------|----------|--------|-----------------|--------------|-------------|-------------|-------------------|---------------|
|Санкт-Петербург|1-до месяца      |1,775     |0.16    |106,717          |54.09         |2            |5            |10                 |1              |
|Санкт-Петербург|2-до трех месяцев|2,997     |0.27    |108,681          |56.22         |2            |5            |12                 |1              |
|Санкт-Петербург|3-до полугода    |2,221     |0.2     |109,618          |60.16         |2            |5            |10                 |1              |
|Санкт-Петербург|4-более полугода |3,454     |0.31    |111,014          |64.89         |2            |5            |10                 |1              |
|Санкт-Петербург|5-не снято       |635       |0.06    |129,184          |80.51         |3            |4            |9                  |1              |
|ЛенОбл         |1-до месяца      |329       |0.12    |73,779           |48.86         |2            |4            |5                  |1              |
|ЛенОбл         |2-до трех месяцев|829       |0.3     |68,433           |50.82         |2            |3            |5                  |1              |
|ЛенОбл         |3-до полугода    |534       |0.2     |71,664           |51.91         |2            |3            |5                  |1              |
|ЛенОбл         |4-более полугода |840       |0.31    |70,186           |55.14         |2            |3            |5                  |1              |
|ЛенОбл         |5-не снято       |189       |0.07    |75,630           |63.28         |2            |3            |5                  |1              |

* И в Санкт-Петербурге, и в Ленинградской области активность большей части объявлений составляет более полугода, 
* а также 2-3 месяца(31% и 27% в Санкт-Петербурге соответственно и 31% и 30% в Ленинградской области). 
* В течение месяца уходит меньше всего квартир: 16% в Санкт-Петербурге и 12% в Ленинградской области. 
* Однако нужно отметить, что быстрее всего в Ленинградской области уходят квартиры дороже по стоимости. 
* А чем дольше висит объявление, тем оно становится дешевле. Можно предположить , что в Ленинградской области 
* есть спрос на новое, более качественное, престижное жилье. В Санкт-Петербурге же более дорогие объекты задерживаются на рынке. 
* Таким образом в Санкт-Петербурге спрос на дешевое жилье, в Ленинградской области на качественное. Из других характеристик 
* можно отметить, что везде быстрее продаются небольшие по площади 1-2 комнатные квартиры с балконом. В Санкт-Петербурге 
* преобладает квартиры до 5 этажа в многоэтажных зданиях, в Ленинградской области - до 3-4 этажа в малоэтажных.
**/


/* Задача2. Выявить периоды с повышенной активностью продавцов и покупателей, 
 * а также оценить характеристики недвижимости в разные сезоны
 */

--Установим локаль для вывода даты и времени
SET lc_time = 'ru_RU';
--Убираем аномальные значения из real_estate.flats
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
--Высчитаем стоимость за кв.метр
    sq_m_price_data AS (
    SELECT id,
    	last_price/total_area AS price_per_sqm
    FROM real_estate.flats
    LEFT JOIN real_estate.advertisement USING (id)),
-- Высчитаем выбросы для стоимости за кв.метр
    limits_2 AS (
    SELECT PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY price_per_sqm) AS price_per_sqm_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY price_per_sqm) AS price_per_sqm_limit_l
     FROM sq_m_price_data),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats 
    JOIN sq_m_price_data USING (id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND (price_per_sqm < (SELECT price_per_sqm_limit_h FROM limits_2) AND price_per_sqm > (SELECT price_per_sqm_limit_l FROM limits_2))    
    ),
-- Выведем нужные параметры объявлений без выбросов только по Санкт-Петербургу и городам Лен.области и за полные года 2015 - 2018
flats_filtered_data AS (
	SELECT id,
		EXTRACT (MONTH FROM first_day_exposition ) AS month_number_expos,--выделяем номер месяца
		TO_CHAR(first_day_exposition, 'TMmon') AS exposition_month,--выделяем месяц публикации объявления
		TO_CHAR (first_day_exposition+(days_exposition*'1 day'::INTERVAL), 'TMmon') AS sale_month,--выделяем месяц снятия объявления
		price_per_sqm,
		total_area
FROM real_estate.flats 
JOIN real_estate.advertisement USING (id)
JOIN sq_m_price_data USING (id)
WHERE id IN (SELECT * FROM filtered_id)
		AND type_id='F8EM' --убираем объявления не в городах
		AND EXTRACT (YEAR FROM first_day_exposition) IN (2015, 2016, 2017, 2018)),-- оставялем данные за полные годы
--Группируем данные по месяцу публикации объявления и высчитываем показатели 
exposition_month_stat AS (
		SELECT ffd.month_number_expos, -- номер месяца
		ffd.exposition_month, --название месяца
		COUNT(ffd.id) AS expos_ads_amount,--кол-во публикаций
		ROUND(AVG(ffd.price_per_sqm)::numeric) AS expos_avg_price_per_sqm,--ср.цена  за кв.м. публикаций
		ROUND(AVG(ffd.total_area)::numeric,2) AS expos_avg_total_area -- ср.площадь
FROM flats_filtered_data AS ffd
GROUP BY ffd.month_number_expos, ffd.exposition_month),
-- Группируем данные по месяцу снятия объявления и высчитываем показатели
sale_month_stat AS (
		SELECT ffd.sale_month, --название месяца
		COUNT(ffd.id) AS sale_ads_amount,--кол-во снятий
		ROUND(AVG(ffd.price_per_sqm)::numeric) AS sale_avg_price_per_sqm,--ср.цена  за кв.м.
		ROUND(AVG(ffd.total_area)::numeric,2) AS sale_avg_total_area -- ср.площадь
FROM flats_filtered_data AS ffd
GROUP BY ffd.sale_month)
--Основной запрос
SELECT emt.exposition_month, 
		emt.expos_ads_amount, 
		ROUND(emt.expos_ads_amount::NUMERIC/SUM(emt.expos_ads_amount) OVER(),2) AS exposition_part, --доля публикаций
		DENSE_RANK() OVER(ORDER BY emt.expos_ads_amount DESC) AS exposition_rank, --ранг по публикациям
		sms.sale_ads_amount, 
		ROUND(sms.sale_ads_amount::NUMERIC/SUM(sms.sale_ads_amount) OVER(),2) AS sale_part, --доля снятий
		DENSE_RANK() OVER(ORDER BY sms.sale_ads_amount DESC) AS sale_rank, --ранг по снятиям
		emt.expos_avg_price_per_sqm, 
		emt.expos_avg_total_area,
		sms.sale_avg_price_per_sqm,
		sms.sale_avg_total_area 
FROM exposition_month_stat AS emt
JOIN sale_month_stat AS sms ON emt.exposition_month=sms.sale_month
ORDER BY emt.month_number_expos; --фильтруем по номеру месяца

/*
 * ВЫВОД:
|exposition_month|expos_ads_amount|exposition_part|exposition_rank|sale_ads_amount|sale_part|sale_rank|expos_avg_price_per_sqm|expos_avg_total_area|sale_avg_price_per_sqm|sale_avg_total_area|
|----------------|----------------|---------------|---------------|---------------|---------|---------|-----------------------|--------------------|----------------------|-------------------|
|янв             |723             |0.05           |12             |1,204          |0.09     |4        |103,799                |58.77               |102,070               |56.65              |
|фев             |1,346           |0.1            |3              |1,032          |0.08     |9        |101,549                |59.56               |103,898               |61.2               |
|мар             |1,102           |0.08           |8              |1,042          |0.08     |8        |101,887                |59.91               |101,973               |59.5               |
|апр             |1,009           |0.07           |9              |1,012          |0.08     |10       |99,847                 |60.18               |101,907               |58.88              |
|мая             |878             |0.06           |11             |723            |0.06     |12       |101,079                |58.85               |99,145                |57.61              |
|июн             |1,187           |0.09           |5              |762            |0.06     |11       |100,654                |57.41               |101,529               |59.47              |
|июл             |1,129           |0.08           |7              |1,085          |0.08     |7        |103,109                |59.93               |99,873                |57.91              |
|авг             |1,144           |0.08           |6              |1,119          |0.09     |6        |105,132                |58.38               |97,547                |56.12              |
|сен             |1,321           |0.1            |4              |1,215          |0.09     |3        |106,442                |60.89               |101,326               |56.9               |
|окт             |1,413           |0.1            |2              |1,340          |0.1      |1        |102,552                |59.1                |103,788               |58.71              |
|ноя             |1,547           |0.11           |1              |1,282          |0.1      |2        |102,977                |59.07               |102,129               |56.55              |
|дек             |1,004           |0.07           |10             |1,163          |0.09     |5        |101,708                |58.33               |104,120               |59.01              |

 
 *Наибольшая активность в публикации объявлений наблюдается в ноябре (1547 объявлений), октябре ( 1413 объявления), 
 *феврале (1346 объявления) и сентябре (1321). По снятию объявлений лидируют октябрь (1340 объявлений), ноябрь (1282 объявления ).
 *Самые дорогие квартиры выкладываются в сентябре (106442), августе (105132) в предверии активного сезона. Дороже всего покупают
 *квартиры в декабре (104120). Самые большие квартиры поступают в продажу в сентябре (60,89 ), самые маленькие – в июне (57,41). 
 *А покупают большие квартиры в феврале (61,2 ), а самые маленькие – в августе (56,12 )
 */

/* Общий вывод: 
 * При рассмотрении объявлений о продаже жилой недвижимости в Санкт- Петербурге и городах Ленинградской области, 
 * можно отметить, что 80% всех объявлений сосредоточены в Санкт-Петербурге. Большая часть объявлений в
 * обоих регионах закрывается в период 2-3 месяца или от 6 месяцев. В Санкт-Петербурге быстрее всего получится 
 * продать недорогое жилье и небольшое по площади. В Ленинградской области спросом также пользуются небольшие
 * объекты, но покупатели готовы оперативно приобретать более дорогие квартиры. Возможно, в данном регионе 
 * есть дефицит качественного, нового жилья. Активные публикации и закрытия объявлений происходят в ноябре-октябре.
 * Подороже заплатить за жилье покупатели готовы в декабре. Дорогие объекты не рекомендуется выкладывать с мая по июль.
 */






		




