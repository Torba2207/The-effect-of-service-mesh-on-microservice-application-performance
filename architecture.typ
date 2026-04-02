= Architecure
== Introduction
To realistically evaluate the impact of a Service Mesh on modern architectures, we require
a tangible and highly representative testbed. Therefore, we have designed a fully functional 
e-commerce microservice platform.\
Our architecture includes core commerce services:Inventory, User, Payment, Product, Order, Discount, Recommendation services and alongside AI Agent.\
To ensure a rigorous testing baseline, we are implementing two key architectural rules:
- Database-per-Service: Each microservice will utilize its own isolated database to guarantee true decoupling.
- Heterogeneous system: the core platform will run on a Kubernetes cluster, but the AI Agent will be hosted on a dedicated Virtual Machine. This ensures we test Service Mesh traffic management and observability across a complex, cross-environment boundary.

== Main elements
- Inventory srvc - number of items in stock, etc. Reserved items(in case if customer already on payment step, but not yet paid)
- User srvc - user account, user data, user history etc. User addresses, user payment methods, etc. (Kirill: we can ask history of users' orders in order srvc)
- Payment srvc - processing payments, connecting to payment gateways, payment history, etc.
- Product srvc - product details, availability(?).
- Recommendation srvc - product recommendations based on user's order history, items in basket, availability of items, etc.
- AI agent srvc - AI agent that can be interacted with by user, answer questions, provide recommendations, etc. It can also interact with other services to get information. Has connection with recommendation srvc, product srvc.
- Order srvc - order realization.
- Discount srvc - discounts, etc.