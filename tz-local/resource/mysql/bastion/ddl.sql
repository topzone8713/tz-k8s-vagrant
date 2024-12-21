GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%';
#GRANT ALL PRIVILEGES ON *.* TO 'root'@'mysql.devops-dev.svc.cluster.local';
FLUSH PRIVILEGES;

-- DROP DATABASE aws_usage;
-- CREATE DATABASE aws_usage
ALTER DATABASE aws_usage
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- DROP TABLE aws_usage.aws_cost;
CREATE table aws_usage.aws_cost (
  lineitemid VARCHAR(45) NOT NULL,
  timeinterval TIMESTAMP NULL,
  invoiceid INT NULL,
  billingentity VARCHAR(45) NULL,
  billtype VARCHAR(45) NULL,
  payeraccountid INT NULL,
  billingperiodstartdate TIMESTAMP NULL,
  billingperiodenddate TIMESTAMP NULL,
  usageaccountid INT NULL,
  lineitemtype VARCHAR(45) NULL,
  usagestartdate TIMESTAMP NULL,
  usageenddate TIMESTAMP NULL,
  productcode VARCHAR(45) NULL,
  usagetype VARCHAR(45) NULL,
  operation VARCHAR(45) NULL,
  availabilityzone VARCHAR(45) NULL,
  resourceid VARCHAR(200) NULL,
  usageamount DOUBLE NULL,
  currencycode VARCHAR(45) NULL,
  unblendedrate DOUBLE NULL,
  unblendedcost DOUBLE NULL,
  lineitemdescription VARCHAR(45) NULL,
  taxtype VARCHAR(45) NULL,
  sku VARCHAR(45) NULL,
  leasecontractlength VARCHAR(45) NULL,
  purchaseoption VARCHAR(45) NULL,
  term VARCHAR(45) NULL,
  productcategory VARCHAR(45) NULL,
  region VARCHAR(45) NULL,
  instancetype VARCHAR(45) NULL,
  tag_application VARCHAR(45) NULL,
  tag_environment VARCHAR(45) NULL,
  tag_name VARCHAR(45) NULL,
  tag_role VARCHAR(45) NULL,
  tag_service VARCHAR(45) NULL,
  tags VARCHAR(45) NULL,
PRIMARY KEY (lineitemid));


-- DROP TABLE aws_usage.aws_cost_inst;
CREATE table aws_usage.aws_cost_inst (
  resourceid VARCHAR(200) NOT NULL,
  billingperiodstartdate VARCHAR(50) NOT NULL,
  region VARCHAR(45) NOT NULL,
  usageamount float NULL,
  usageaccountid INT NULL,
  productcode VARCHAR(45) NULL,
  currencycode VARCHAR(45) NULL,
PRIMARY KEY (resourceid, billingperiodstartdate, region));


INSERT INTO aws_usage.aws_cost_inst
SELECT distinct C.resourceid, billingperiodstartdate, region, B.usageamount, usageaccountid, productcode, currencycode
FROM (
	SELECT resource, usageamount
	FROM (
		SELECT CONCAT(resourceid, billingperiodstartdate, region) as resource, SUM(usageamount) AS usageamount
		FROM aws_usage.aws_cost
		where resourceid <> '' and usageamount > 0.1
		GROUP BY CONCAT(resourceid, billingperiodstartdate, region)
	) A
	WHERE A.usageamount > 200
) B, aws_usage.aws_cost C
WHERE B.resource = CONCAT(C.resourceid, C.billingperiodstartdate, C.region);


-- DROP TABLE aws_usage.aws_cost_inst2;
CREATE table aws_usage.aws_cost_inst2 (
  resourceid VARCHAR(200) NOT NULL,
  billingperiodstartdate VARCHAR(50) NOT NULL,
  region VARCHAR(45) NOT NULL,
  usageamount float NULL,
  usageaccountid INT NULL,
  productcode VARCHAR(45) NULL,
  currencycode VARCHAR(45) NULL,
PRIMARY KEY (resourceid, billingperiodstartdate, region));

DELETE FROM aws_usage.aws_cost_inst2;
INSERT INTO aws_usage.aws_cost_inst2
SELECT distinct C.resourceid, billingperiodstartdate, region, B.usageamount, usageaccountid, productcode, currencycode
FROM (
	SELECT resource, usageamount
	FROM (
		SELECT CONCAT(resourceid, billingperiodstartdate, region) as resource, SUM(usageamount) AS usageamount
		FROM aws_usage.aws_cost
		where resourceid <> ''
		AND productcode in ('AmazonElastiCache', 'AmazonRDS', 'AmazonEC2', 'AmazonES')
		GROUP BY CONCAT(resourceid, billingperiodstartdate, region)
	) A
	WHERE A.usageamount > 1
) B, aws_usage.aws_cost C
WHERE B.resource = CONCAT(C.resourceid, C.billingperiodstartdate, C.region)
AND C.productcode in ('AmazonElastiCache', 'AmazonRDS', 'AmazonEC2', 'AmazonES');

