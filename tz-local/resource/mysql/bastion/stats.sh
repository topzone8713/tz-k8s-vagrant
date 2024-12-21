#!/usr/bin/env bash

cd /vagrant/tz-local/resource/mysql

SELECT DISTINCT productcategory, productcode
FROM aws_usage.aws_cost;

SELECT *
FROM aws_usage.aws_cost
where productcategory like '%RDS%'
LIMIT 1;

SELECT productcode, max(unblendedcost) as max1, sum(unblendedcost) as sum2, count(unblendedcost) as count1
FROM aws_usage.aws_cost
AND billingperiodenddate BETWEEN '2021-08-01 00:00:00' AND '2021-09-01 00:00:00'
group by productcode;

SELECT productcode, max(unblendedcost) as max1, sum(unblendedcost) as sum2, count(unblendedcost) as count1
FROM aws_usage.aws_cost
where productcode = 'AmazonRDS'
AND billingperiodenddate BETWEEN '2021-08-01 00:00:00' AND '2021-09-01 00:00:00'
group by productcode;


SELECT A.resourceid, A.amount
FROM (
    SELECT resourceid, sum(unblendedcost) as amount
    FROM aws_usage.aws_cost
    where productcategory like '%RDS%'
    group by resourceid
) A
ORDER BY A.amount desc;
;



SELECT A.resourceid, A.productcategory, productcode, A.amount
FROM (
    SELECT resourceid, productcategory, productcode,
      sum(unblendedcost) as amount
    FROM aws_usage.aws_cost
    WHERE billingperiodenddate BETWEEN '2021-06-01 00:00:00' AND '2021-07-01 00:00:00'
    group by resourceid, productcategory, productcode
) A
ORDER BY A.amount desc
LIMIT 50
INTO OUTFILE '/tmp/myoutput2.txt';

SELECT 1p, SUM(1a) AS 1s, 2p, SUM(2a) AS 2s, 3p, SUM(3a) AS 3s
FROM (
  SELECT * FROM (
    SELECT A.productcode AS 1p, A.amount AS 1a, A.productcode AS 2p, 0 AS 2a, A.productcode AS 3p, 0 AS 3a
    FROM (
        SELECT productcode, sum(unblendedcost) as amount
        FROM aws_usage.aws_cost
        WHERE billingperiodenddate BETWEEN '2021-06-01 00:00:00' AND '2021-07-01 00:00:00'
        group by productcode
    ) A
    ORDER BY A.amount desc
  ) A1
  UNION ALL
  SELECT * FROM (
    SELECT B.productcode AS 1p, 0  AS 1a, B.productcode AS 2p, B.amount AS 2a, B.productcode AS 3p, 0 AS 3a
    FROM (
        SELECT productcode, sum(unblendedcost) as amount
        FROM aws_usage.aws_cost
        WHERE billingperiodenddate BETWEEN '2021-07-01 00:00:00' AND '2021-08-01 00:00:00'
        group by productcode
    ) B
    ORDER BY B.amount desc
  ) B1
  UNION ALL
  SELECT * FROM (
    SELECT C.productcode AS 1p, 0  AS 1a, C.productcode AS 2p, 0 AS 2a, C.productcode AS 3p, C.amount AS 3a
    FROM (
        SELECT productcode, sum(unblendedcost) as amount
        FROM aws_usage.aws_cost
        WHERE billingperiodenddate BETWEEN '2021-08-01 00:00:00' AND '2021-09-01 00:00:00'
        group by productcode
    ) C
    ORDER BY C.amount desc
  ) C1
  LIMIT 100
) A0
GROUP BY 1p, 2p, 3p
ORDER BY 3s DESC

INTO OUTFILE '/tmp/myoutput3.txt';


        SELECT productcode, sum(unblendedcost) as amount
        FROM aws_usage.aws_cost
        WHERE billingperiodenddate BETWEEN '2021-06-01 00:00:00' AND '2021-07-01 00:00:00'
        AND productcode = 'AmazonRDS'
        group by productcode;


        SELECT productcode, sum(unblendedcost) as amount
        FROM aws_usage.aws_cost
        WHERE billingperiodenddate BETWEEN '2021-07-01 00:00:00' AND '2021-08-01 00:00:00'
        AND productcode = 'AmazonRDS'
        group by productcode;

DELETE FROM aws_usage.aws_cost
WHERE billingperiodenddate BETWEEN '2021-07-01 00:00:00' AND '2021-08-01 00:00:00'

        SELECT productcode, sum(unblendedcost) as amount
        FROM aws_usage.aws_cost
        WHERE billingperiodenddate BETWEEN '2021-08-01 00:00:00' AND '2021-09-01 00:00:00'
        AND productcode = 'AmazonRDS'
        group by productcode;


SELECT Sum(unblendedcost) FROM aws_usage.aws_cost
WHERE billingperiodenddate BETWEEN '2021-05-01 00:00:00' AND '2021-06-01 00:00:00';
53,075,248

SELECT COUNT(1) FROM aws_usage.aws_cost
WHERE billingperiodenddate BETWEEN '2021-05-01 00:00:00' AND '2021-06-01 00:00:00';
1038932

SELECT COUNT(1) FROM aws_usage.aws_cost
WHERE billingperiodenddate BETWEEN '2021-06-01 00:00:00' AND '2021-07-01 00:00:00';
1108249

SELECT COUNT(1) FROM aws_usage.aws_cost
WHERE billingperiodenddate BETWEEN '2021-07-01 00:00:00' AND '2021-08-01 00:00:00';
977644

SELECT COUNT(1) FROM aws_usage.aws_cost
WHERE billingperiodenddate BETWEEN '2021-08-01 00:00:00' AND '2021-09-01 00:00:00';
399560

# download output to local
kubectl cp devops-dev/mysql-5d94bc4676-22xp9:tmp/myoutput3.txt /vagrant/tz-local/resource/mysql/bastion/myoutput.txt

exit 0

productcode

'AmazonECS'
'AWSDataTransfer'
'AmazonS3'
'AmazonEC2'
'AmazonCloudFront'
'AmazonRoute53'
'AWSELB'
'AmazonRDS'
'AmazonECR'
'AmazonCloudWatch'
'awskms'
'AmazonLightsail'
'AWSQueueService'
'AmazonElastiCache'
'AWSSecretsManager'
'AmazonEKS'
'AmazonSNS'
'AWSLambda'
'AmazonES'
'AmazonStates'
'AmazonSES'
'AmazonDynamoDB'
'AWSServiceCatalog'
'ElasticMapReduce'
'AmazonApiGateway'
'AmazonSageMaker'
'awswaf'
'AmazonEFS'
'AWSSupportBusiness'
'AWSGlue'
'AmazonMSK'
'ComputeSavingsPlans'
'AmazonKinesisFirehose'


productcategory
'Etc'
'Amazon Data Transfer Multi Region'
'Amazon Web Service Requests'
'EBS'
'Amazon Web Service Storage Usage'
'Amazon CloudFront HTTPS'
'Bandwidth'
'Amazon CloudFront HTTP'
'Amazon Route53 Queries'
'Amazon Data Transfer from/to CloudFront'
'Instance Usage'
'Instance Usage (Size Flexibility Applied)'
'Elastic Load Balancing'
'Amazon RDS Service Storage'
'Amazon CloudWatch'
'Reserved Instance Monthly Prepayment'
'Savings Plan Covered Usage'
'Amazon CloudWatch PutLogEvents'
'Amazon Route53 HostedZone'
'Amazon RDS Service AutomatedBackUp'
'Amazon Elasticsearch Service Storage'
'Amazon Simple Email Service Send'
'Reserved Instance Monthly Prepayment (Size Fl'
'Amazon CloudFront Invalidations'
'Amazon DynamoDB Capacity'
'Amazon Simple Notification Service Delivery A'
'Amazon Elasticsearch Service ESDomain'
'AWS Support'
'Amazon Elastic Cache Backup Usage'
'Elastic IP Address'
'Savings Plan Recurring Fee'

