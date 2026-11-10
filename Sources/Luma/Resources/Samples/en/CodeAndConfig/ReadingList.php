<?php
declare(strict_types=1);

$documents = [
    ['title' => 'Design notes', 'read' => true],
    ['title' => 'Lab notes', 'read' => false],
];

foreach ($documents as $document) {
    if (!$document['read']) {
        echo $document['title'] . PHP_EOL;
    }
}
