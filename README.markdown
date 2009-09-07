Twilter - a twitter filter
==========================

Broad architecture
------------------

Twilter is split into three types of script:

* _Collectors_: which fetch new tweets from the Twitter API, and queue them up for...
* _Classifiers_: which subject new tweets to a test to categorise the tweet according to priority, spamminess and so forth, and then store them in the database for...
* _Circulators_: which broadcast new tweets if they are appropriate for the current context
